import 'dart:convert';

import '../../models/attachment.dart';
import '../../models/chat_message.dart';
import '../../models/citation.dart';
import '../../models/conversation.dart';
import '../../models/usage_report.dart';
import '../chat_service.dart';
import '../streaming/sse_client.dart';
import 'anthropic_api_config.dart';
import 'anthropic_stream_accumulator.dart';
import 'anthropic_tools.dart';
import 'provider_registry.dart';

/// Raw-HTTP Anthropic Messages API client (no official Dart SDK exists).
/// The request builder and SSE→ChatEvent mapper are pure and unit-tested;
/// only [streamChat]/[validateKey] touch the network.
class AnthropicClient implements KeyValidatable {
  final SseClient _sse;

  AnthropicClient({SseClient? sseClient}) : _sse = sseClient ?? SseClient();

  /// Builds the Messages API body for one turn. [conversation] supplies the
  /// prior turns; [userInput]+[attachments] form the new user message.
  static Map<String, dynamic> buildRequestBody({
    required Conversation conversation,
    required String userInput,
    required String model,
    List<Attachment> attachments = const [],
    String? systemPrompt,
    bool stream = true,
    bool extendedThinking = true,
    int maxTokens = AnthropicApiConfig.defaultMaxTokens,
  }) {
    // The store already appends this turn's own user message (plus an
    // empty streaming placeholder for the reply) to [conversation] before
    // handing it to a ChatService. Both are dropped from history here since
    // the new user turn is re-added below (with this call's attachments) —
    // otherwise it would be duplicated as two consecutive user messages.
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

    final messages = <Map<String, dynamic>>[];
    for (final message in history) {
      if (message.text.trim().isEmpty) continue;
      switch (message.role) {
        case MessageRole.user:
          messages.add({
            'role': 'user',
            'content': _contentBlocks(message.text, message.attachments),
          });
        case MessageRole.assistant:
          messages.add({'role': 'assistant', 'content': message.text});
        case MessageRole.system:
          break; // folded into the system param, never a message row
      }
    }
    messages.add({
      'role': 'user',
      'content': _contentBlocks(userInput, attachments),
    });

    return {
      'model': model,
      'max_tokens': maxTokens,
      if (systemPrompt != null && systemPrompt.isNotEmpty)
        'system': systemPrompt,
      'messages': messages,
      // Adaptive thinking on capable models; 'display' is required — without
      // it the visible text can come back empty. Never send temperature —
      // current models reject it.
      if (extendedThinking && AnthropicApiConfig.thinkingModels.contains(model))
        'thinking': {'type': 'adaptive', 'display': 'summarized'},
      if (stream) 'stream': true,
    };
  }

  /// Attachments become image/document source blocks ahead of the text.
  static List<Map<String, dynamic>> _contentBlocks(
    String text,
    List<Attachment> attachments,
  ) {
    final blocks = <Map<String, dynamic>>[];
    for (final attachment in attachments) {
      final bytes = attachment.bytes;
      if (bytes == null) continue;
      switch (attachment.kind) {
        case AttachmentKind.image:
          blocks.add({
            'type': 'image',
            'source': {
              'type': 'base64',
              'media_type': attachment.mimeType,
              'data': base64Encode(bytes),
            },
          });
        case AttachmentKind.pdf:
          blocks.add({
            'type': 'document',
            'source': {
              'type': 'base64',
              'media_type': 'application/pdf',
              'data': base64Encode(bytes),
            },
          });
        case AttachmentKind.text:
          blocks.add({
            'type': 'text',
            'text': 'Attached file "${attachment.name}":\n'
                '${utf8.decode(bytes, allowMalformed: true)}',
          });
      }
    }
    blocks.add({'type': 'text', 'text': text.isEmpty ? '(see attachment)' : text});
    return blocks;
  }

  /// Maps the Messages API SSE event stream onto the app's [ChatEvent]
  /// vocabulary. Emits [UsageReported] then [MessageComplete] at the end.
  static Stream<ChatEvent> mapSseEvents(
    Stream<SseEvent> events, {
    required String model,
  }) async* {
    var inputTokens = 0;
    var outputTokens = 0;
    String? stopReason;

    await for (final event in events) {
      if (event.data.isEmpty) continue;
      Map<String, dynamic> payload;
      try {
        payload = jsonDecode(event.data) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      switch (event.event) {
        case 'message_start':
          final usage =
              (payload['message'] as Map<String, dynamic>?)?['usage'];
          if (usage is Map) {
            inputTokens = usage['input_tokens'] as int? ?? 0;
          }
        case 'content_block_delta':
          final delta = payload['delta'] as Map<String, dynamic>?;
          switch (delta?['type']) {
            case 'text_delta':
              yield MessageDelta(delta!['text'] as String? ?? '');
            case 'thinking_delta':
              yield ThinkingDelta(delta!['thinking'] as String? ?? '');
          }
        case 'message_delta':
          final delta = payload['delta'] as Map<String, dynamic>?;
          stopReason = delta?['stop_reason'] as String? ?? stopReason;
          final usage = payload['usage'] as Map<String, dynamic>?;
          if (usage != null) {
            outputTokens = usage['output_tokens'] as int? ?? outputTokens;
          }
        case 'error':
          final error = payload['error'] as Map<String, dynamic>?;
          yield MessageError(
              error?['message'] as String? ?? 'Unknown API error');
          return;
      }
    }

    if (stopReason == 'refusal') {
      yield const MessageError(
          'The model declined to answer this request.');
      return;
    }
    yield UsageReported(UsageReport(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      model: AnthropicApiConfig.displayName(model),
    ));
    yield const MessageComplete();
  }

  /// Streams one chat turn against the live API, with optional server
  /// tools. Server-side tool loops that hit the API's iteration limit end
  /// with `stop_reason: "pause_turn"` — the turn is resumed automatically
  /// (re-sending the accumulated assistant blocks; the server detects the
  /// trailing tool block and picks up where it left off), capped at
  /// [maxContinuations] rounds.
  Stream<ChatEvent> streamChat({
    required String apiKey,
    required Conversation conversation,
    required String userInput,
    required String model,
    List<Attachment> attachments = const [],
    String? systemPrompt,
    List<Map<String, dynamic>> tools = const [],
    bool extendedThinking = true,
    int maxContinuations = 5,
  }) async* {
    final baseBody = buildRequestBody(
      conversation: conversation,
      userInput: userInput,
      model: model,
      attachments: attachments,
      systemPrompt: systemPrompt,
      extendedThinking: extendedThinking,
    );
    if (tools.isNotEmpty) baseBody['tools'] = tools;

    final headers = AnthropicApiConfig.headers(apiKey);
    if (tools.any((t) => (t['type'] as String? ?? '').startsWith('code_execution'))) {
      headers['anthropic-beta'] = AnthropicTools.codeExecutionBeta;
    }

    final messages =
        List<Map<String, dynamic>>.from(baseBody['messages'] as List);
    var inputTokens = 0;
    var outputTokens = 0;
    final allCitations = <String, Citation>{};

    for (var round = 0; round <= maxContinuations; round++) {
      final accumulator = AnthropicStreamAccumulator();
      final body = {...baseBody, 'messages': messages};
      final sseEvents = _sse.postJson(
        uri: AnthropicApiConfig.messagesEndpoint,
        headers: headers,
        body: jsonEncode(body),
      );

      await for (final sseEvent in sseEvents) {
        for (final chatEvent in accumulator.onSseEvent(sseEvent)) {
          if (chatEvent is MessageError) {
            yield chatEvent;
            return;
          }
          yield chatEvent;
        }
      }

      inputTokens += accumulator.inputTokens;
      outputTokens += accumulator.outputTokens;
      for (final citation in accumulator.citations) {
        allCitations[citation.url] = citation;
      }

      if (accumulator.stopReason == 'refusal') {
        yield const MessageError(
            'The model declined to answer this request.');
        return;
      }
      if (accumulator.stopReason == 'pause_turn' &&
          round < maxContinuations) {
        // No extra user message — just the assistant's partial turn.
        messages.add({
          'role': 'assistant',
          'content': accumulator.contentBlocks,
        });
        continue;
      }
      break;
    }

    if (allCitations.isNotEmpty) {
      yield CitationsReady(allCitations.values.toList());
    }
    yield UsageReported(UsageReport(
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      model: AnthropicApiConfig.displayName(model),
    ));
    yield const MessageComplete();
  }

  /// Small non-streaming call to classify a prompt or validate a key.
  /// Returns the assistant text.
  Future<String> complete({
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    int maxTokens = 200,
  }) async {
    final events = _sse.postJson(
      uri: AnthropicApiConfig.messagesEndpoint,
      headers: AnthropicApiConfig.headers(apiKey),
      body: jsonEncode({
        'model': model,
        'max_tokens': maxTokens,
        if (systemPrompt != null) 'system': systemPrompt,
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'stream': true,
      }),
    );
    final buffer = StringBuffer();
    await for (final chatEvent in mapSseEvents(events, model: model)) {
      if (chatEvent is MessageDelta) buffer.write(chatEvent.chunk);
      if (chatEvent is MessageError) throw Exception(chatEvent.message);
    }
    return buffer.toString();
  }

  /// Cheap key check. Returns null on success or a human-readable problem.
  @override
  Future<String?> validateKey(String apiKey) async {
    try {
      await complete(
        apiKey: apiKey,
        model: AnthropicApiConfig.haikuModel,
        prompt: 'Reply with OK.',
        maxTokens: 8,
      );
      return null;
    } on SseHttpException catch (e) {
      return switch (e.statusCode) {
        401 => 'That key was rejected (401). Double-check it in '
            'console.anthropic.com → API keys.',
        429 => 'Key works but you\'re rate-limited right now (429).',
        529 => 'Anthropic\'s API is overloaded (529) — try again shortly.',
        _ => 'API error ${e.statusCode}: ${e.body}',
      };
    } catch (e) {
      return 'Could not reach api.anthropic.com — a network filter or '
          'offline connection may be blocking it. ($e)';
    }
  }
}
