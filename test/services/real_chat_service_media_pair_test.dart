import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/models/chat_message.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/models/studio_result.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/persistence_service.dart';
import 'package:shift_ai/services/providers/anthropic_client.dart';
import 'package:shift_ai/services/providers/gemini_client.dart';
import 'package:shift_ai/services/real_chat_service.dart';
import 'package:shift_ai/state/api_keys_store.dart';

class _ScriptWritingAnthropic extends AnthropicClient {
  @override
  Future<String> complete({
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    int maxTokens = 200,
  }) async =>
      'Hi, I\'m your guide — let me show you around.';
}

class _PortraitGeminiClient extends GeminiClient {
  int calls = 0;
  @override
  Stream<ChatEvent> generateImage({
    required String apiKey,
    required String prompt,
  }) async* {
    calls++;
    yield ImageGenerated(pngBytes: Uint8List.fromList([1, 2, 3]), alt: 'x');
    yield const MessageComplete();
  }
}

Conversation _fresh(String userInput) => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
      messages: [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: userInput,
          timestamp: DateTime(2026, 7, 20),
        ),
        ChatMessage(
          id: 'a1',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: '',
          status: MessageStatus.streaming,
          timestamp: DateTime(2026, 7, 20),
        ),
      ],
    );

Future<ApiKeysStore> _keys({required bool gemini}) async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  await keys.setAnthropicKey('test-anthropic-key');
  if (gemini) await keys.setGeminiKey('test-gemini-key');
  return keys;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a live talking avatar uses Gemini for the portrait and Claude for '
      'the voiceover script', () async {
    final keys = await _keys(gemini: true);
    final gemini = _PortraitGeminiClient();
    final service = RealChatService(
      keys: keys,
      anthropicClient: _ScriptWritingAnthropic(),
      geminiClient: gemini,
    );

    final events = await service
        .sendMessage(
          conversation: _fresh('make a talking avatar that says hello'),
          userInput: 'make a talking avatar that says hello',
        )
        .toList();

    expect(gemini.calls, 1);
    expect(events.whereType<ImageGenerated>(), hasLength(1));
    final result = events.whereType<StudioResultReady>().single.result;
    expect((result as AudioResult).transcript,
        'Hi, I\'m your guide — let me show you around.');
    expect(events.last, isA<MessageComplete>());
  });

  test('with no Gemini key, the avatar portrait falls back to procedural art',
      () async {
    final keys = await _keys(gemini: false);
    final gemini = _PortraitGeminiClient();
    final service = RealChatService(
      keys: keys,
      anthropicClient: _ScriptWritingAnthropic(),
      geminiClient: gemini,
    );

    final events = await service
        .sendMessage(
          conversation: _fresh('make a talking avatar'),
          userInput: 'make a talking avatar',
        )
        .toList();

    expect(gemini.calls, 0);
    expect(events.whereType<ImageGenerated>(), hasLength(1));
    expect(events.whereType<StudioResultReady>().single.result,
        isA<AudioResult>());
  });
}
