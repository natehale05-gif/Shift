import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/providers/clients/provider_access.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/providers/clients/openai_compatible_client.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';

/// Records the arguments of the one streamChat call and emits a scripted
/// reply, so the test asserts the pin routed to the right provider/model
/// without any network.
class _RecordingOpenAi extends OpenAiCompatibleClient {
  String? seenBaseUrl;
  String? seenModel;
  String? seenApiKey;
  Map<String, String>? seenHeaders;

  @override
  Stream<ChatEvent> streamChat({
    required ProviderAccess access,
    required String baseUrl,
    required String model,
    required Conversation conversation,
    required String userInput,
    String displayName = '',
    List<dynamic> attachments = const [],
    String? systemPrompt,
    Map<String, String> extraHeaders = const {},
  }) async* {
    // The pin test cares that the *member's own* key was used, which is now
    // what a DirectKey carries.
    seenApiKey = access is DirectKey ? access.key : null;
    seenBaseUrl = baseUrl;
    seenModel = model;
    seenHeaders = extraHeaders;
    yield const MessageDelta('Hi from GPT.');
    yield const MessageComplete();
  }

  // The router classifies via complete() when only an OpenAI-compatible key
  // exists; keep it offline and route everything to plain chat.
  @override
  Future<String> complete({
    required String apiKey,
    required String baseUrl,
    required String model,
    required String prompt,
    String? systemPrompt,
    Map<String, String> extraHeaders = const {},
    int maxTokens = 400,
  }) async =>
      '{"route":"chat"}';
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

Future<ApiKeysStore> _keys(Map<String, String> providerKeys) async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  for (final entry in providerKeys.entries) {
    await keys.setKey(entry.key, entry.value);
  }
  return keys;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pinning a GPT model routes the turn to OpenAI with that model',
      () async {
    final keys = await _keys({'openai': 'sk-openai-123'});
    final openAi = _RecordingOpenAi();
    final service = RealChatService(keys: keys, openAiClient: openAi);

    final events = await service
        .sendMessage(
          conversation: _fresh('hello there'),
          userInput: 'hello there',
          options: const ChatOptions(modelPin: 'gpt-4o'),
        )
        .toList();

    expect(openAi.seenBaseUrl, 'https://api.openai.com/v1');
    expect(openAi.seenModel, 'gpt-4o');
    expect(openAi.seenApiKey, 'sk-openai-123');
    expect(events.whereType<MessageDelta>().map((e) => e.chunk).join(),
        'Hi from GPT.');
    expect(events.last, isA<MessageComplete>());
  });

  test('OpenRouter pin carries the descriptor extra headers and base url',
      () async {
    final keys = await _keys({'openrouter': 'sk-or-xyz'});
    final openAi = _RecordingOpenAi();
    final service = RealChatService(keys: keys, openAiClient: openAi);

    await service
        .sendMessage(
          conversation: _fresh('hi'),
          userInput: 'hi',
          options: const ChatOptions(modelPin: 'openai/gpt-4o'),
        )
        .toList();

    expect(openAi.seenBaseUrl, 'https://openrouter.ai/api/v1');
    expect(openAi.seenModel, 'openai/gpt-4o');
    expect(openAi.seenHeaders?['X-Title'], 'SHIFT AI');
  });

  test('Auto (no pin): an OpenAI-only user gets live GPT text, not the mock',
      () async {
    final keys = await _keys({'openai': 'sk-openai-123'});
    final openAi = _RecordingOpenAi();
    final service = RealChatService(keys: keys, openAiClient: openAi);

    final events = await service
        .sendMessage(
          conversation: _fresh('tell me a fun fact'),
          userInput: 'tell me a fun fact',
        )
        .toList();

    // Routed to OpenAI's default chat model with no pin.
    expect(openAi.seenBaseUrl, 'https://api.openai.com/v1');
    expect(openAi.seenModel, 'gpt-4o');
    expect(events.whereType<MessageDelta>().map((e) => e.chunk).join(),
        'Hi from GPT.');
    expect(events.last, isA<MessageComplete>());
  });

  test('pinning a provider with no key does not dispatch to OpenAI', () async {
    // A GPT pin but only a (mock) state with no OpenAI key -> the OpenAI
    // client is never called; the request degrades through the normal path.
    final keys = await _keys({});
    final openAi = _RecordingOpenAi();
    final service = RealChatService(keys: keys, openAiClient: openAi);

    await service
        .sendMessage(
          conversation: _fresh('hi'),
          userInput: 'hi',
          options: const ChatOptions(modelPin: 'gpt-4o'),
        )
        .toList();

    expect(openAi.seenModel, isNull);
  });
}
