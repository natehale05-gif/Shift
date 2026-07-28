import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/providers/clients/gemini_api_config.dart';
import 'package:shift_ai/providers/clients/gemini_client.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/providers/router/model_router.dart';

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

void main() {
  group('buildRequestBody', () {
    test('maps roles to user/model and layers system + grounding', () {
      final body = GeminiClient.buildRequestBody(
        conversation: _history(),
        userInput: 'what is new today?',
        systemPrompt: 'You are SHIFT AI.',
        grounding: true,
      );

      final contents = body['contents'] as List;
      expect(contents, hasLength(3));
      expect((contents[1] as Map)['role'], 'model');
      expect(
        ((body['systemInstruction'] as Map)['parts'] as List).single,
        {'text': 'You are SHIFT AI.'},
      );
      expect((body['tools'] as List).single, {'google_search': {}});
      expect(body.containsKey('generationConfig'), isFalse);
    });

    test('does not duplicate the new user turn when the store has already '
        'appended it to history', () {
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

      final body = GeminiClient.buildRequestBody(
        conversation: conversation,
        userInput: 'new question',
      );

      final contents = body['contents'] as List;
      expect(contents, hasLength(3));
      expect((contents[0] as Map)['role'], 'user');
      expect((contents[1] as Map)['role'], 'model');
      expect((contents[2] as Map)['role'], 'user');
    });

    test('image output requests TEXT+IMAGE modalities', () {
      final body = GeminiClient.buildRequestBody(
        conversation: Conversation(
          id: '_',
          title: '_',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
        userInput: 'a watercolor fox',
        imageOutput: true,
      );
      expect(
        (body['generationConfig'] as Map)['responseModalities'],
        ['TEXT', 'IMAGE'],
      );
    });
  });

  group('mapChunk', () {
    test('text parts, grounding chunks, and usage all extract', () {
      final (events, citations, usage) = GeminiClient.mapChunk({
        'candidates': [
          {
            'content': {
              'role': 'model',
              'parts': [
                {'text': 'Grounded answer.'},
              ],
            },
            'groundingMetadata': {
              'groundingChunks': [
                {
                  'web': {'uri': 'https://g.test/a', 'title': 'Source A'},
                },
              ],
            },
          },
        ],
        'usageMetadata': {
          'promptTokenCount': 12,
          'candidatesTokenCount': 34,
        },
      }, model: GeminiApiConfig.flashModel);

      expect(events.whereType<MessageDelta>().single.chunk,
          'Grounded answer.');
      expect(citations.single.title, 'Source A');
      expect(usage!.inputTokens, 12);
      expect(usage.outputTokens, 34);
      expect(usage.model, 'Gemini 2.5 Flash');
    });

    test('inlineData becomes an ImageGenerated event', () {
      final (events, _, _) = GeminiClient.mapChunk({
        'candidates': [
          {
            'content': {
              'parts': [
                {
                  'inlineData': {
                    'mimeType': 'image/png',
                    'data': 'iVBORw0KGgo=',
                  },
                },
              ],
            },
          },
        ],
      }, model: GeminiApiConfig.imageModel);

      final image = events.whereType<ImageGenerated>().single;
      expect(image.pngBytes, isNotEmpty);
    });
  });

  group('chooseExecutor degradation matrix', () {
    test('all 9 combos land on the best available provider', () {
      // No keys → everything mocks.
      for (final route in [ChatRoute.chat, ChatRoute.webSearch, ChatRoute.imageGen]) {
        expect(
          chooseExecutor(route, hasAnthropic: false, hasGemini: false),
          Executor.mock,
        );
      }
      // Anthropic only.
      expect(chooseExecutor(ChatRoute.chat, hasAnthropic: true, hasGemini: false),
          Executor.anthropic);
      expect(
          chooseExecutor(ChatRoute.webSearch,
              hasAnthropic: true, hasGemini: false),
          Executor.anthropic);
      expect(
          chooseExecutor(ChatRoute.imageGen,
              hasAnthropic: true, hasGemini: false),
          Executor.mock,
          reason: 'image generation needs Gemini');
      // Gemini only.
      expect(chooseExecutor(ChatRoute.chat, hasAnthropic: false, hasGemini: true),
          Executor.gemini);
      expect(
          chooseExecutor(ChatRoute.webSearch,
              hasAnthropic: false, hasGemini: true),
          Executor.gemini);
      expect(
          chooseExecutor(ChatRoute.imageGen,
              hasAnthropic: false, hasGemini: true),
          Executor.gemini);
      // Both → Claude for text, Gemini for images; video/audio always mock.
      expect(chooseExecutor(ChatRoute.code, hasAnthropic: true, hasGemini: true),
          Executor.anthropic);
      expect(
          chooseExecutor(ChatRoute.imageGen,
              hasAnthropic: true, hasGemini: true),
          Executor.gemini);
      expect(chooseExecutor(ChatRoute.video, hasAnthropic: true, hasGemini: true),
          Executor.mock);
    });
  });
}
