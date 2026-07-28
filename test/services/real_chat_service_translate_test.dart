import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_result.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/providers/clients/anthropic_client.dart';
import 'package:shift_ai/services/real_chat_service.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';

/// A stub Anthropic client whose complete() returns a canned "translation",
/// so the test proves the translate path calls a real provider and wraps the
/// output as a live TranslateResult — no network.
class _StubAnthropic extends AnthropicClient {
  String? seenPrompt;
  @override
  Future<String> complete({
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    int maxTokens = 200,
  }) async {
    seenPrompt = prompt;
    return 'Hola mundo';
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

Future<ApiKeysStore> _keys() async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  await keys.setAnthropicKey('sk-ant-test');
  return keys;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a live user gets a real, downloadable translation', () async {
    final keys = await _keys();
    final anthropic = _StubAnthropic();
    final service = RealChatService(keys: keys, anthropicClient: anthropic);

    final events = await service
        .sendMessage(
          conversation: _fresh('translate to Spanish: Hello world'),
          userInput: 'translate to Spanish: Hello world',
        )
        .toList();

    expect(events.whereType<RoutingDetected>().single.studioType.name,
        'translateStudio');
    final result = events.whereType<StudioResultReady>().single.result;
    expect(result, isA<TranslateResult>());
    final t = result as TranslateResult;
    expect(t.targetLanguage, 'Spanish');
    expect(t.sourceText, 'Hello world');
    expect(t.translatedText, 'Hola mundo');
    expect(t.live, isTrue);
    // The provider was asked to translate into Spanish.
    expect(anthropic.seenPrompt, contains('into Spanish'));
  });

  test('asks for the text when only a language is given', () async {
    final keys = await _keys();
    final service = RealChatService(keys: keys, anthropicClient: _StubAnthropic());

    final events = await service
        .sendMessage(
          conversation: _fresh('translate this into French'),
          userInput: 'translate this into French',
        )
        .toList();

    expect(events.whereType<StudioResultReady>(), isEmpty);
    expect(
        events.whereType<MessageDelta>().map((e) => e.chunk).join(),
        contains('French'));
  });
}
