import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/providers/clients/provider_access.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_result.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/turn/backends/mock_backend.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/providers/clients/anthropic_client.dart';
import 'package:shift_ai/providers/clients/heygen_client.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';

class _ScriptAnthropic extends AnthropicClient {
  @override
  Future<String> complete({
    required String apiKey,
    required String model,
    required String prompt,
    String? systemPrompt,
    int maxTokens = 200,
  }) async =>
      'Hi, I am your presenter.';
}

class _FakeHeygen extends HeygenClient {
  int calls = 0;
  @override
  Future<HeygenVideo> generateAvatarVideo({
    required ProviderAccess access,
    required String script,
    String? avatarId,
    String? voiceId,
  }) async {
    calls++;
    return const HeygenVideo(
        videoUrl: 'https://cdn.heygen/a.mp4', thumbnailUrl: 'https://cdn.heygen/a.jpg');
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

Future<List<ChatEvent>> _mock(String prompt) =>
    MockChatService().sendMessage(conversation: _fresh(prompt), userInput: prompt).toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('live Avatar studio renders a real Heygen video, attributed to Avatar',
      () async {
    final keys = await _keys({'anthropic': 'sk-ant', 'heygen': 'hg'});
    final heygen = _FakeHeygen();
    final service = RealChatService(
      keys: keys,
      anthropicClient: _ScriptAnthropic(),
      heygenClient: heygen,
    );

    final events = await service
        .sendMessage(
          conversation: _fresh('make a talking head avatar of our founder'),
          userInput: 'make a talking head avatar of our founder',
        )
        .toList();

    expect(heygen.calls, 1);
    expect(events.whereType<RoutingDetected>().first.studioType,
        StudioType.avatarStudio);
    final result = events.whereType<StudioResultReady>().single.result;
    expect(result, isA<VideoResult>());
    expect((result as VideoResult).videoUrl, 'https://cdn.heygen/a.mp4');
  });

  test('mock Avatar studio shows a portrait + a voice card', () async {
    final events = await _mock('make a talking head avatar of me');
    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.avatarStudio);
    expect(events.whereType<ImageGenerated>(), hasLength(1));
    expect(events.whereType<StudioResultReady>().single.result, isA<AudioResult>());
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('mock Voice studio produces a downloadable voiceover card', () async {
    final events = await _mock('record a voiceover for my intro');
    expect(events.whereType<RoutingDetected>().single.studioType,
        StudioType.voiceStudio);
    final result = events.whereType<StudioResultReady>().single.result;
    expect(result, isA<AudioResult>());
    expect((result as AudioResult).kind, AudioKind.voice);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
