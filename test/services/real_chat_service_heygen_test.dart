import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/models/chat_message.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/models/studio_result.dart';
import 'package:shift_ai/services/chat_service.dart';
import 'package:shift_ai/services/persistence_service.dart';
import 'package:shift_ai/services/providers/anthropic_client.dart';
import 'package:shift_ai/services/providers/heygen_client.dart';
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
      'Welcome to Northbound.';
}

class _FakeHeygen extends HeygenClient {
  int calls = 0;
  String? seenScript;
  final bool fail;
  _FakeHeygen({this.fail = false});

  @override
  Future<HeygenVideo> generateAvatarVideo({
    required String apiKey,
    required String script,
    String avatarId = '',
    String voiceId = '',
  }) async {
    calls++;
    seenScript = script;
    if (fail) throw Exception('render failed');
    return const HeygenVideo(
      videoUrl: 'https://cdn.heygen/out.mp4',
      thumbnailUrl: 'https://cdn.heygen/out.jpg',
    );
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

Future<ApiKeysStore> _keys(Map<String, String> keys) async {
  SharedPreferences.setMockInitialValues({});
  final store = ApiKeysStore(persistence: PersistenceService());
  await store.load();
  for (final e in keys.entries) {
    await store.setKey(e.key, e.value);
  }
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a talking avatar with a Heygen key becomes a real Heygen video card',
      () async {
    final keys = await _keys({'anthropic': 'sk-ant', 'heygen': 'hg-key'});
    final heygen = _FakeHeygen();
    final service = RealChatService(
      keys: keys,
      anthropicClient: _ScriptWritingAnthropic(),
      heygenClient: heygen,
    );

    final events = await service
        .sendMessage(
          conversation: _fresh('make a talking avatar that says hello'),
          userInput: 'make a talking avatar that says hello',
        )
        .toList();

    expect(heygen.calls, 1);
    expect(heygen.seenScript, 'Welcome to Northbound.');
    final result = events.whereType<StudioResultReady>().single.result;
    expect(result, isA<VideoResult>());
    final video = result as VideoResult;
    expect(video.isRealVideo, isTrue);
    expect(video.videoUrl, 'https://cdn.heygen/out.mp4');
    expect(video.posterUrl, 'https://cdn.heygen/out.jpg');
    expect(video.providerLabel, 'Heygen');
    // The avatar path emits no separate portrait image for a real render.
    expect(events.whereType<ImageGenerated>(), isEmpty);
  });

  test('when the Heygen render fails, the avatar falls back to the simulated '
      'portrait + voice card', () async {
    final keys = await _keys({'anthropic': 'sk-ant', 'heygen': 'hg-key'});
    final heygen = _FakeHeygen(fail: true);
    final service = RealChatService(
      keys: keys,
      anthropicClient: _ScriptWritingAnthropic(),
      heygenClient: heygen,
    );

    final events = await service
        .sendMessage(
          conversation: _fresh('make a talking avatar'),
          userInput: 'make a talking avatar',
        )
        .toList();

    expect(heygen.calls, 1);
    // Fallback: a portrait image + an audio (voice) card, no video.
    expect(events.whereType<ImageGenerated>(), hasLength(1));
    expect(events.whereType<StudioResultReady>().single.result,
        isA<AudioResult>());
  });

  test('without a Heygen key, a talking avatar stays image + voice (Heygen '
      'never called)', () async {
    final keys = await _keys({'anthropic': 'sk-ant'});
    final heygen = _FakeHeygen();
    final service = RealChatService(
      keys: keys,
      anthropicClient: _ScriptWritingAnthropic(),
      heygenClient: heygen,
    );

    final events = await service
        .sendMessage(
          conversation: _fresh('make a talking avatar'),
          userInput: 'make a talking avatar',
        )
        .toList();

    expect(heygen.calls, 0);
    expect(events.whereType<StudioResultReady>().single.result,
        isA<AudioResult>());
  });
}
