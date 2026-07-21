import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../models/attachment.dart';
import '../../models/chat_message.dart';
import '../../models/citation.dart';
import '../../models/conversation.dart';
import '../../models/usage_report.dart';
import '../chat_service.dart';
import '../streaming/http_client_stub.dart'
    if (dart.library.html) '../streaming/http_client_web.dart';
import '../streaming/sse_client.dart';
import 'gemini_api_config.dart';
import 'provider_registry.dart';

/// Raw-HTTP Gemini client: streaming chat (optionally grounded with Google
/// Search) and image generation. Pure request builder and chunk mapper are
/// unit-tested; only the send methods touch the network.
class GeminiClient implements KeyValidatable {
  final SseClient _sse;
  final http.Client Function() _clientFactory;

  GeminiClient({SseClient? sseClient, http.Client Function()? clientFactory})
      : _sse = sseClient ?? SseClient(),
        _clientFactory = clientFactory ?? createStreamingClient;

  static Map<String, dynamic> buildRequestBody({
    required Conversation conversation,
    required String userInput,
    List<Attachment> attachments = const [],
    String? systemPrompt,
    bool grounding = false,
    bool imageOutput = false,
  }) {
    // The store already appends this turn's own user message (plus an
    // empty streaming placeholder for the reply) to [conversation] before
    // handing it to a ChatService. Both are dropped from history here since
    // the new user turn is re-added below — otherwise it would be
    // duplicated as two consecutive user turns.
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

    final contents = <Map<String, dynamic>>[];
    for (final message in history) {
      if (message.text.trim().isEmpty) continue;
      switch (message.role) {
        case MessageRole.user:
          contents.add({
            'role': 'user',
            'parts': [
              {'text': message.text},
            ],
          });
        case MessageRole.assistant:
          contents.add({
            'role': 'model',
            'parts': [
              {'text': message.text},
            ],
          });
        case MessageRole.system:
          break;
      }
    }
    contents.add({
      'role': 'user',
      'parts': [
        for (final attachment in attachments)
          if (attachment.bytes != null)
            {
              'inlineData': {
                'mimeType': attachment.mimeType,
                'data': base64Encode(attachment.bytes!),
              },
            },
        {'text': userInput.isEmpty ? '(see attachment)' : userInput},
      ],
    });

    return {
      'contents': contents,
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        'systemInstruction': {
          'parts': [
            {'text': systemPrompt},
          ],
        },
      if (grounding)
        'tools': [
          {'google_search': <String, dynamic>{}},
        ],
      if (imageOutput)
        'generationConfig': {
          'responseModalities': ['TEXT', 'IMAGE'],
        },
    };
  }

  /// Extracts the app's events from one streamed (or whole) response chunk.
  /// Returns (chatEvents, citations, usage?) — citations and usage
  /// accumulate across chunks.
  static (List<ChatEvent>, List<Citation>, UsageReport?) mapChunk(
    Map<String, dynamic> chunk, {
    required String model,
  }) {
    final events = <ChatEvent>[];
    final citations = <Citation>[];
    UsageReport? usage;

    final candidates = chunk['candidates'] as List<dynamic>? ?? const [];
    if (candidates.isNotEmpty) {
      final candidate = candidates.first as Map<String, dynamic>;
      final parts = ((candidate['content']
              as Map<String, dynamic>?)?['parts'] as List<dynamic>?) ??
          const [];
      for (final part in parts) {
        final map = part as Map<String, dynamic>;
        final text = map['text'] as String?;
        if (text != null && text.isNotEmpty) {
          events.add(MessageDelta(text));
        }
        final inline = map['inlineData'] as Map<String, dynamic>?;
        final data = inline?['data'] as String?;
        if (data != null) {
          events.add(ImageGenerated(
            pngBytes: base64Decode(data),
            alt: 'Generated image',
          ));
        }
      }

      final grounding =
          candidate['groundingMetadata'] as Map<String, dynamic>?;
      final chunks = grounding?['groundingChunks'] as List<dynamic>?;
      if (chunks != null) {
        for (final entry in chunks) {
          final web = (entry as Map<String, dynamic>)['web']
              as Map<String, dynamic>?;
          final uri = web?['uri'] as String?;
          if (uri != null) {
            citations.add(Citation(
              url: uri,
              title: web?['title'] as String? ?? uri,
            ));
          }
        }
      }
    }

    final usageMetadata = chunk['usageMetadata'] as Map<String, dynamic>?;
    if (usageMetadata != null) {
      usage = UsageReport(
        inputTokens: usageMetadata['promptTokenCount'] as int? ?? 0,
        outputTokens: usageMetadata['candidatesTokenCount'] as int? ?? 0,
        model: GeminiApiConfig.displayName(model),
      );
    }
    return (events, citations, usage);
  }

  /// Streams a chat turn (optionally grounded via Google Search).
  Stream<ChatEvent> streamChat({
    required String apiKey,
    required Conversation conversation,
    required String userInput,
    String model = GeminiApiConfig.flashModel,
    List<Attachment> attachments = const [],
    String? systemPrompt,
    bool grounding = false,
  }) async* {
    final body = buildRequestBody(
      conversation: conversation,
      userInput: userInput,
      attachments: attachments,
      systemPrompt: systemPrompt,
      grounding: grounding,
    );

    final allCitations = <String, Citation>{};
    UsageReport? usage;

    final events = _sse.postJson(
      uri: GeminiApiConfig.streamEndpoint(model, apiKey),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode(body),
    );

    await for (final event in events) {
      if (event.data.isEmpty) continue;
      Map<String, dynamic> chunk;
      try {
        chunk = jsonDecode(event.data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final (chatEvents, citations, chunkUsage) =
          mapChunk(chunk, model: model);
      for (final chatEvent in chatEvents) {
        yield chatEvent;
      }
      for (final citation in citations) {
        allCitations[citation.url] = citation;
      }
      usage = chunkUsage ?? usage;
    }

    if (allCitations.isNotEmpty) {
      yield CitationsReady(allCitations.values.toList());
    }
    if (usage != null) yield UsageReported(usage);
    yield const MessageComplete();
  }

  /// Generates an image (plus any accompanying text) in one call.
  Stream<ChatEvent> generateImage({
    required String apiKey,
    required String prompt,
  }) async* {
    final response = await _postJson(
      GeminiApiConfig.generateEndpoint(GeminiApiConfig.imageModel, apiKey),
      buildRequestBody(
        conversation: Conversation(
          id: '_',
          title: '_',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        userInput: prompt,
        imageOutput: true,
      ),
    );
    final (events, _, usage) =
        mapChunk(response, model: GeminiApiConfig.imageModel);
    var sawImage = false;
    for (final event in events) {
      if (event is ImageGenerated) sawImage = true;
      yield event;
    }
    if (!sawImage) {
      yield const MessageError(
          'Gemini returned no image for this prompt — try rewording it.');
      return;
    }
    if (usage != null) yield UsageReported(usage);
    yield const MessageComplete();
  }

  Future<Map<String, dynamic>> _postJson(
      Uri uri, Map<String, dynamic> body) async {
    final client = _clientFactory();
    try {
      final response = await client.post(
        uri,
        headers: const {'content-type': 'application/json'},
        body: jsonEncode(body),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw SseHttpException(response.statusCode, response.body);
      }
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }

  /// Small completion used for routing classification and synthesis.
  Future<String> complete({
    required String apiKey,
    required String prompt,
    String? systemPrompt,
    String model = GeminiApiConfig.flashModel,
  }) async {
    final response = await _postJson(
      GeminiApiConfig.generateEndpoint(model, apiKey),
      buildRequestBody(
        conversation: Conversation(
          id: '_',
          title: '_',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
        userInput: prompt,
        systemPrompt: systemPrompt,
      ),
    );
    final (events, _, _) = mapChunk(response, model: model);
    return events.whereType<MessageDelta>().map((e) => e.chunk).join();
  }

  /// Cheap key check. Returns null on success or a human-readable problem
  /// (raw error bodies included on purpose — they make endpoint drift
  /// diagnosable).
  @override
  Future<String?> validateKey(String apiKey) async {
    try {
      await complete(apiKey: apiKey, prompt: 'Reply with OK.');
      return null;
    } on SseHttpException catch (e) {
      return switch (e.statusCode) {
        400 || 403 =>
          'That key was rejected (${e.statusCode}). Create one at '
              'aistudio.google.com. Raw response: ${e.body}',
        429 => 'Key works but you\'re rate-limited right now (429).',
        _ => 'API error ${e.statusCode}: ${e.body}',
      };
    } catch (e) {
      return 'Could not reach generativelanguage.googleapis.com — a network '
          'filter or offline connection may be blocking it. ($e)';
    }
  }

  Uint8List? firstImageBytes(List<ChatEvent> events) {
    for (final event in events) {
      if (event is ImageGenerated) return event.pngBytes;
    }
    return null;
  }
}
