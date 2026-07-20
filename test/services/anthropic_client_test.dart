import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/models/attachment.dart';
import 'package:shift_ai/models/chat_message.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/providers/anthropic_api_config.dart';
import 'package:shift_ai/services/providers/anthropic_client.dart';
import 'package:shift_ai/services/streaming/sse_client.dart';

Conversation _history() => Conversation(
      id: 'c1',
      title: 'History',
      createdAt: DateTime(2026, 7, 19),
      updatedAt: DateTime(2026, 7, 19),
      messages: [
        ChatMessage(
          id: 'm1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: 'earlier question',
          timestamp: DateTime(2026, 7, 19, 9),
        ),
        ChatMessage(
          id: 'm2',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: 'earlier answer',
          timestamp: DateTime(2026, 7, 19, 9, 1),
        ),
      ],
    );

/// Recorded-shape Anthropic SSE stream for one streamed reply with
/// thinking, two text deltas, and usage.
const _sseFixture = '''
event: message_start
data: {"type":"message_start","message":{"id":"msg_1","usage":{"input_tokens":42}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"Considering the question."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":" world"}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":9}}

event: message_stop
data: {"type":"message_stop"}
''';

const _refusalFixture = '''
event: message_start
data: {"type":"message_start","message":{"id":"msg_2","usage":{"input_tokens":10}}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"refusal"},"usage":{"output_tokens":0}}

event: message_stop
data: {"type":"message_stop"}
''';

Stream<SseEvent> _eventsFromFixture(String fixture) =>
    parseSseLines(Stream.fromIterable(const LineSplitter().convert(fixture)));

void main() {
  group('parseSseLines', () {
    test('accumulates event/data pairs and dispatches on blank lines',
        () async {
      final events = await _eventsFromFixture(_sseFixture).toList();
      expect(events, hasLength(8));
      expect(events.first.event, 'message_start');
      expect(events.first.data, contains('"input_tokens":42'));
    });

    test('handles multi-line data fields', () async {
      final events = await parseSseLines(Stream.fromIterable([
        'event: test',
        'data: line1',
        'data: line2',
        '',
      ])).toList();
      expect(events.single.data, 'line1\nline2');
    });
  });

  group('buildRequestBody', () {
    test('golden shape: thinking model, system, history, no temperature',
        () {
      final body = AnthropicClient.buildRequestBody(
        conversation: _history(),
        userInput: 'new question',
        model: AnthropicApiConfig.defaultModel,
        systemPrompt: 'You are SHIFT AI.',
      );

      expect(body['model'], 'claude-opus-4-8');
      expect(body['system'], 'You are SHIFT AI.');
      expect(body['stream'], isTrue);
      expect(body['thinking'],
          {'type': 'adaptive', 'display': 'summarized'});
      expect(body.containsKey('temperature'), isFalse);
      expect(body.containsKey('top_p'), isFalse);

      final messages = body['messages'] as List;
      expect(messages, hasLength(3));
      expect((messages[1] as Map)['role'], 'assistant');
      final last = messages.last as Map;
      expect(last['role'], 'user');
      final lastContent = (last['content'] as List).last as Map;
      expect(lastContent['text'], 'new question');
    });

    test('haiku gets no thinking parameter', () {
      final body = AnthropicClient.buildRequestBody(
        conversation: _history(),
        userInput: 'route this',
        model: AnthropicApiConfig.haikuModel,
      );
      expect(body.containsKey('thinking'), isFalse);
    });

    test('image attachments become base64 source blocks before the text',
        () {
      final body = AnthropicClient.buildRequestBody(
        conversation: Conversation(
          id: 'c2',
          title: 'x',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        userInput: 'what is in this image?',
        model: AnthropicApiConfig.defaultModel,
        attachments: [
          Attachment(
            id: 'a1',
            name: 'photo.png',
            mimeType: 'image/png',
            kind: AttachmentKind.image,
            bytes: Uint8List.fromList([1, 2, 3]),
          ),
        ],
      );
      final content =
          ((body['messages'] as List).single as Map)['content'] as List;
      expect((content[0] as Map)['type'], 'image');
      expect(((content[0] as Map)['source'] as Map)['media_type'],
          'image/png');
      expect((content[1] as Map)['type'], 'text');
    });
  });

  group('mapSseEvents', () {
    test('maps deltas, usage, and completion', () async {
      final events = await AnthropicClient.mapSseEvents(
        _eventsFromFixture(_sseFixture),
        model: AnthropicApiConfig.defaultModel,
      ).toList();

      expect(
        events.whereType<ThinkingDelta>().single.chunk,
        'Considering the question.',
      );
      final text = events
          .whereType<MessageDelta>()
          .map((e) => e.chunk)
          .join();
      expect(text, 'Hello world');
      final usage = events.whereType<UsageReported>().single.usage;
      expect(usage.inputTokens, 42);
      expect(usage.outputTokens, 9);
      expect(usage.model, 'Claude Opus 4.8');
      expect(events.last, isA<MessageComplete>());
    });

    test('refusal stop reason becomes a readable error, not completion',
        () async {
      final events = await AnthropicClient.mapSseEvents(
        _eventsFromFixture(_refusalFixture),
        model: AnthropicApiConfig.defaultModel,
      ).toList();

      expect(events.whereType<MessageError>(), hasLength(1));
      expect(events.whereType<MessageComplete>(), isEmpty);
    });
  });
}
