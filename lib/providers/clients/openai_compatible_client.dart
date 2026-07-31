import 'dart:convert';

import '../../data/models/attachment.dart';
import '../../data/models/chat_message.dart';
import '../../data/models/conversation.dart';
import '../../data/models/usage_report.dart';
import '../../turn/chat_service.dart';
import '../streaming/sse_client.dart';
import 'openai_compatible_config.dart';
import 'provider_access.dart';
import '../history/conversation_history.dart';

/// One raw-HTTP client for every OpenAI-compatible provider (OpenAI, Groq,
/// OpenRouter, Mistral). They share the chat-completions wire shape and differ
/// only by base URL / model / extra headers, all passed in per call — so a new
/// such provider is a descriptor, not a client. Reuses [SseClient.postJson]
/// (its [parseSseLines] already handles OpenAI `data:` framing and `[DONE]`).
class OpenAiCompatibleClient {
  final SseClient _sse;

  OpenAiCompatibleClient({SseClient? sseClient})
      : _sse = sseClient ?? SseClient();

  /// Builds the chat-completions body. Mirrors the Anthropic/Gemini clients:
  /// the store has already appended this turn's user message plus an empty
  /// streaming placeholder, so both are dropped from history before the new
  /// user turn is re-added (with this call's attachments).
  static Map<String, dynamic> buildRequestBody({
    required Conversation conversation,
    required String userInput,
    required String model,
    List<Attachment> attachments = const [],
    String? systemPrompt,
    bool stream = true,
  }) {
    final history = List.of(conversation.messages);
    if (history.isNotEmpty &&
        history.last.role == MessageRole.assistant &&
        history.last.text.trim().isEmpty) {
      history.removeLast();
      if (history.isNotEmpty &&
          history.last.role == MessageRole.user &&
          history.last.text == userInput) {
        history.removeLast();
      }
    }

    final messages = <Map<String, dynamic>>[
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        {'role': 'system', 'content': systemPrompt},
    ];
    // Images are left out of the history here, unlike Claude and Gemini: this
    // one client serves GPT, Groq, Mistral and OpenRouter, and not all of
    // those models take images. They get the notes instead — a real capability
    // difference, rather than the accidental data loss this replaces.
    for (final turn in buildHistory(history, includeImages: false)) {
      messages.add({
        'role': turn.role == MessageRole.user ? 'user' : 'assistant',
        'content': turn.text,
      });
    }
    messages.add({'role': 'user', 'content': _userContent(userInput, attachments)});

    return {
      'model': model,
      'messages': messages,
      if (stream) ...{
        'stream': true,
        'stream_options': {'include_usage': true},
      },
    };
  }

  /// A plain string when there are no attachments; otherwise the multimodal
  /// content-array form (text + `image_url` data URIs; text files are inlined).
  static Object _userContent(String text, List<Attachment> attachments) {
    if (attachments.isEmpty) {
      return text.isEmpty ? '(see attachment)' : text;
    }
    final parts = <Map<String, dynamic>>[];
    for (final attachment in attachments) {
      final bytes = attachment.bytes;
      if (bytes == null) continue;
      switch (attachment.kind) {
        case AttachmentKind.image:
          parts.add({
            'type': 'image_url',
            'image_url': {
              'url': 'data:${attachment.mimeType};base64,${base64Encode(bytes)}',
            },
          });
        case AttachmentKind.pdf:
          // OpenAI-compatible chat completions have no portable PDF block;
          // note it so the model at least knows a file was attached.
          parts.add({
            'type': 'text',
            'text': 'Attached PDF "${attachment.name}" (content not inlined).',
          });
        case AttachmentKind.text:
          parts.add({
            'type': 'text',
            'text': 'Attached file "${attachment.name}":\n'
                '${utf8.decode(bytes, allowMalformed: true)}',
          });
      }
    }
    parts.add({'type': 'text', 'text': text.isEmpty ? '(see attachment)' : text});
    return parts;
  }

  /// Maps the chat-completions SSE stream onto the app's [ChatEvent]
  /// vocabulary. Pure — unit-tested against recorded fixtures.
  static Stream<ChatEvent> mapSseEvents(
    Stream<SseEvent> events, {
    required String displayName,
  }) async* {
    var inputTokens = 0;
    var outputTokens = 0;

    await for (final event in events) {
      final data = event.data.trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') break;
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final choices = payload['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final delta =
            (choices.first as Map<String, dynamic>)['delta'] as Map<String, dynamic>?;
        final content = delta?['content'] as String?;
        if (content != null && content.isNotEmpty) {
          yield MessageDelta(content);
        }
      }
      final usage = payload['usage'] as Map<String, dynamic>?;
      if (usage != null) {
        inputTokens = usage['prompt_tokens'] as int? ?? inputTokens;
        outputTokens = usage['completion_tokens'] as int? ?? outputTokens;
      }
    }

    yield UsageReported(UsageReport(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      model: displayName,
    ));
    yield const MessageComplete();
  }

  /// Streams one chat turn against a provider's chat-completions endpoint.
  Stream<ChatEvent> streamChat({
    required ProviderAccess access,
    required String baseUrl,
    required String model,
    required Conversation conversation,
    required String userInput,
    String displayName = '',
    List<Attachment> attachments = const [],
    String? systemPrompt,
    Map<String, String> extraHeaders = const {},
  }) {
    final body = buildRequestBody(
      conversation: conversation,
      userInput: userInput,
      model: model,
      attachments: attachments,
      systemPrompt: systemPrompt,
    );
    // `baseUrl` still identifies the provider when the call is direct. Through
    // the proxy the base is SHIFT's, and the provider is named by the path the
    // server was given — so the client is not the thing deciding which
    // company's key gets spent.
    final (uri, headers) = switch (access) {
      DirectKey(:final key) => (
          OpenAiCompatibleConfig.chatCompletionsEndpoint(baseUrl),
          OpenAiCompatibleConfig.headers(key, extraHeaders: extraHeaders),
        ),
      ManagedAccess(:final base, headers: final auth) => (
          ManagedAccess(base: base, headers: const {})
              .resolve(OpenAiCompatibleConfig.chatCompletionsPath),
          {'content-type': 'application/json', ...extraHeaders, ...auth},
        ),
    };

    final events = _sse.postJson(
      uri: uri,
      headers: headers,
      body: jsonEncode(body),
    );
    return mapSseEvents(events,
        displayName: displayName.isEmpty ? model : displayName);
  }

  /// Small non-streaming completion (routing/synthesis/validation). Returns the
  /// assistant text.
  Future<String> complete({
    required String apiKey,
    required String baseUrl,
    required String model,
    required String prompt,
    String? systemPrompt,
    Map<String, String> extraHeaders = const {},
    int maxTokens = 400,
  }) async {
    final events = _sse.postJson(
      uri: OpenAiCompatibleConfig.chatCompletionsEndpoint(baseUrl),
      headers: OpenAiCompatibleConfig.headers(apiKey, extraHeaders: extraHeaders),
      body: jsonEncode({
        'model': model,
        'messages': [
          if (systemPrompt != null && systemPrompt.isNotEmpty)
            {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': prompt},
        ],
        'max_tokens': maxTokens,
        'stream': true,
        'stream_options': {'include_usage': true},
      }),
    );
    final buffer = StringBuffer();
    await for (final event in mapSseEvents(events, displayName: model)) {
      if (event is MessageDelta) buffer.write(event.chunk);
      if (event is MessageError) throw Exception(event.message);
    }
    return buffer.toString();
  }

  /// Cheap key check against [baseUrl] using [model]. Returns null on success,
  /// else a human-readable problem (raw error bodies included, matching the
  /// other clients, so endpoint/model drift is diagnosable).
  Future<String?> validateKey({
    required String apiKey,
    required String baseUrl,
    required String model,
    String providerName = 'this provider',
    String consoleUrl = '',
    Map<String, String> extraHeaders = const {},
  }) async {
    try {
      await complete(
        apiKey: apiKey,
        baseUrl: baseUrl,
        model: model,
        prompt: 'Reply with OK.',
        maxTokens: 8,
        extraHeaders: extraHeaders,
      );
      return null;
    } on SseHttpException catch (e) {
      return switch (e.statusCode) {
        401 || 403 => 'That key was rejected (${e.statusCode}). '
            '${consoleUrl.isEmpty ? '' : 'Check it at $consoleUrl. '}'
            'Raw response: ${e.body}',
        404 => 'Endpoint or model not found (404) for $providerName. '
            'Raw response: ${e.body}',
        429 => 'Key works but you\'re rate-limited right now (429).',
        _ => 'API error ${e.statusCode}: ${e.body}',
      };
    } catch (e) {
      return 'Could not reach $providerName — a network filter, CORS, or '
          'offline connection may be blocking it. ($e)';
    }
  }
}
