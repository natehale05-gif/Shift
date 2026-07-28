import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/providers/clients/openai_compatible_client.dart';
import 'package:shift_ai/providers/clients/openai_compatible_config.dart';
import 'package:shift_ai/providers/streaming/sse_client.dart';

Conversation _history() => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      messages: [
        ChatMessage(
          id: 'm1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: 'hi',
          timestamp: DateTime(2026),
        ),
        ChatMessage(
          id: 'm2',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: 'hello!',
          timestamp: DateTime(2026),
        ),
      ],
    );

Stream<SseEvent> _sse(List<String> datas) async* {
  for (final d in datas) {
    yield SseEvent(event: '', data: d);
  }
}

void main() {
  group('OpenAiCompatibleConfig', () {
    test('builds the chat-completions endpoint, tolerating a trailing slash',
        () {
      expect(
          OpenAiCompatibleConfig.chatCompletionsEndpoint('https://api.openai.com/v1')
              .toString(),
          'https://api.openai.com/v1/chat/completions');
      expect(
          OpenAiCompatibleConfig.chatCompletionsEndpoint('https://api.groq.com/openai/v1/')
              .toString(),
          'https://api.groq.com/openai/v1/chat/completions');
    });

    test('headers carry bearer auth plus any extra headers', () {
      final h = OpenAiCompatibleConfig.headers('sk-123',
          extraHeaders: {'X-Title': 'SHIFT AI'});
      expect(h['authorization'], 'Bearer sk-123');
      expect(h['content-type'], 'application/json');
      expect(h['X-Title'], 'SHIFT AI');
    });
  });

  group('buildRequestBody', () {
    test('maps roles, layers a leading system message, and streams', () {
      final body = OpenAiCompatibleClient.buildRequestBody(
        conversation: _history(),
        userInput: 'what next?',
        model: 'gpt-4o',
        systemPrompt: 'You are SHIFT AI.',
      );
      final messages = body['messages'] as List;
      expect((messages.first as Map)['role'], 'system');
      expect((messages.first as Map)['content'], 'You are SHIFT AI.');
      expect((messages[1] as Map)['role'], 'user');
      expect((messages[2] as Map)['role'], 'assistant');
      expect((messages.last as Map)['content'], 'what next?');
      expect(body['model'], 'gpt-4o');
      expect(body['stream'], true);
      expect((body['stream_options'] as Map)['include_usage'], true);
    });

    test('does not duplicate the new user turn when the store already '
        'appended it (with an empty assistant placeholder)', () {
      final conversation = Conversation(
        id: 'c2',
        title: 'x',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        messages: [
          ..._history().messages,
          ChatMessage(
            id: 'm3',
            conversationId: 'c2',
            role: MessageRole.user,
            text: 'new question',
            timestamp: DateTime(2026),
          ),
          ChatMessage(
            id: 'm4',
            conversationId: 'c2',
            role: MessageRole.assistant,
            text: '',
            status: MessageStatus.streaming,
            timestamp: DateTime(2026),
          ),
        ],
      );
      final body = OpenAiCompatibleClient.buildRequestBody(
        conversation: conversation,
        userInput: 'new question',
        model: 'gpt-4o',
      );
      final userTurns = (body['messages'] as List)
          .where((m) => (m as Map)['role'] == 'user' && m['content'] == 'new question');
      expect(userTurns, hasLength(1));
    });
  });

  group('mapSseEvents', () {
    test('accumulates deltas, reads usage, and stops at [DONE]', () async {
      final events = await OpenAiCompatibleClient.mapSseEvents(
        _sse([
          '{"choices":[{"delta":{"content":"Hel"}}]}',
          '{"choices":[{"delta":{"content":"lo"}}]}',
          '{"choices":[{"delta":{}}],"usage":{"prompt_tokens":5,"completion_tokens":2}}',
          '[DONE]',
          '{"choices":[{"delta":{"content":"IGNORED"}}]}',
        ]),
        displayName: 'GPT-4o',
      ).toList();

      final text = events
          .whereType<MessageDelta>()
          .map((e) => e.chunk)
          .join();
      expect(text, 'Hello');
      final usage = events.whereType<UsageReported>().single.usage;
      expect(usage.inputTokens, 5);
      expect(usage.outputTokens, 2);
      expect(usage.model, 'GPT-4o');
      expect(events.last, isA<MessageComplete>());
    });

    test('ignores malformed chunks without crashing', () async {
      final events = await OpenAiCompatibleClient.mapSseEvents(
        _sse(['not json', '{"choices":[{"delta":{"content":"ok"}}]}', '[DONE]']),
        displayName: 'x',
      ).toList();
      expect(events.whereType<MessageDelta>().single.chunk, 'ok');
    });
  });
}
