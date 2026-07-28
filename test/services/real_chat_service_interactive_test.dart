import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/providers/clients/anthropic_client.dart';
import 'package:shift_ai/providers/clients/gemini_client.dart';
import 'package:shift_ai/services/real_chat_service.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';

/// Returns canned recipe JSON, proving the interactive path fills real content.
class _RecipeAnthropic extends AnthropicClient {
  @override
  Future<String> complete({
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    int maxTokens = 200,
  }) async =>
      '{"title":"Real Banana Bread","servings":8,"minutes":60,'
      '"ingredients":[{"qty":"3","item":"ripe bananas"},{"qty":"2 cups","item":"flour"}],'
      '"steps":["Mash the bananas","Mix and bake at 175C for 55 min"]}';
}

class _PhotoGemini extends GeminiClient {
  int calls = 0;
  @override
  Stream<ChatEvent> generateImage({
    required String apiKey,
    required String prompt,
  }) async* {
    calls++;
    yield ImageGenerated(pngBytes: Uint8List.fromList([1, 2, 3, 4]), alt: 'x');
    yield const MessageComplete();
  }
}

Conversation _fresh(String input) => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
      messages: [
        ChatMessage(
            id: 'u1',
            conversationId: 'c1',
            role: MessageRole.user,
            text: input,
            timestamp: DateTime(2026, 7, 20)),
        ChatMessage(
            id: 'a1',
            conversationId: 'c1',
            role: MessageRole.assistant,
            text: '',
            status: MessageStatus.streaming,
            timestamp: DateTime(2026, 7, 20)),
      ],
    );

Future<ApiKeysStore> _keys(Map<String, String> k) async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  for (final e in k.entries) {
    await keys.setKey(e.key, e.value);
  }
  return keys;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a keyed user gets a real recipe card with a Gemini hero photo',
      () async {
    final keys = await _keys({'anthropic': 'sk-ant', 'gemini': 'g'});
    final gemini = _PhotoGemini();
    final service = RealChatService(
      keys: keys,
      anthropicClient: _RecipeAnthropic(),
      geminiClient: gemini,
    );

    final events = await service
        .sendMessage(
          conversation: _fresh('make a recipe card for banana bread'),
          userInput: 'make a recipe card for banana bread',
        )
        .toList();

    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.codeStudio);
    final artifact = events.whereType<ArtifactCreated>().single.artifact;
    // Real content from the provider.
    expect(artifact.title, 'Real Banana Bread');
    expect(artifact.latest.content, contains('ripe bananas'));
    expect(artifact.latest.content, contains('Mash the bananas'));
    // Interactive widget preserved.
    expect(artifact.latest.content, contains('Start timer'));
    // Image Studio contributed a hero photo (Gemini called, bytes embedded).
    expect(gemini.calls, 1);
    final b64 = base64Encode(Uint8List.fromList([1, 2, 3, 4]));
    expect(artifact.latest.content, contains('data:image/png;base64,$b64'));
  });

  test('a text-only keyed user still gets real quiz content', () async {
    final keys = await _keys({'anthropic': 'sk-ant'});
    final service = RealChatService(
      keys: keys,
      anthropicClient: _QuizAnthropic(),
    );

    final events = await service
        .sendMessage(
          conversation: _fresh('quiz me on the planets'),
          userInput: 'quiz me on the planets',
        )
        .toList();

    final artifact = events.whereType<ArtifactCreated>().single.artifact;
    expect(artifact.latest.content, contains('Which planet is red?'));
    expect(artifact.latest.content, contains('Check answers'));
  });
}

class _QuizAnthropic extends AnthropicClient {
  @override
  Future<String> complete({
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    int maxTokens = 200,
  }) async =>
      '[{"question":"Which planet is red?","options":["Mars","Venus","Earth","Jupiter"],"answerIndex":0}]';
}
