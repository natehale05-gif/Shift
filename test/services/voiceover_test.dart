import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/data/models/conversation.dart';
import 'package:shift_ai/data/models/studio_result.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';
import 'package:shift_ai/providers/clients/elevenlabs_client.dart';
import 'package:shift_ai/providers/router/model_router.dart';
import 'package:shift_ai/turn/backends/live_backend.dart';
import 'package:shift_ai/turn/chat_service.dart';
import 'package:shift_ai/turn/studio_detection.dart';

class _ForcedRouter extends ModelRouter {
  final ChatRoute answer;
  _ForcedRouter(this.answer);

  @override
  Future<ChatRoute> route({
    required String input,
    String? anthropicKey,
    String? geminiKey,
  }) async =>
      answer;
}

class _FakeElevenLabs extends ElevenLabsClient {
  int callCount = 0;
  String? spokenText;
  final bool fail;

  _FakeElevenLabs({this.fail = false});

  @override
  Future<Uint8List> speak({
    required String apiKey,
    required String text,
    String voiceId = ElevenLabsClient.defaultVoiceId,
    String model = ElevenLabsClient.defaultModel,
  }) async {
    callCount++;
    spokenText = text;
    if (fail) throw Exception('boom');
    // Not real speech — it only has to come back as bytes on the card.
    return Uint8List.fromList(List.filled(2048, 7));
  }
}

Conversation _conversation(String userInput) => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 30),
      updatedAt: DateTime(2026, 7, 30),
      messages: [
        ChatMessage(
          id: 'u1',
          conversationId: 'c1',
          role: MessageRole.user,
          text: userInput,
          timestamp: DateTime(2026, 7, 30),
        ),
        ChatMessage(
          id: 'a1',
          conversationId: 'c1',
          role: MessageRole.assistant,
          text: '',
          status: MessageStatus.streaming,
          timestamp: DateTime(2026, 7, 30),
        ),
      ],
    );

Future<(List<ChatEvent>, _FakeElevenLabs)> _run(
  String prompt, {
  ChatRoute route = ChatRoute.voice,
  bool withKey = true,
  bool fail = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final keys = ApiKeysStore(persistence: PersistenceService());
  await keys.load();
  if (withKey) await keys.setKey('elevenlabs', 'test-elevenlabs-key');
  final client = _FakeElevenLabs(fail: fail);
  final service = RealChatService(
    keys: keys,
    elevenLabsClient: client,
    router: _ForcedRouter(route),
  );
  final events = await service
      .sendMessage(conversation: _conversation(prompt), userInput: prompt)
      .toList();
  return (events, client);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('what counts as a request for speech', () {
    test('"generate audio talking about X" reaches Voice Studio', () {
      // It matched no keyword table at all, so the turn came out as a plain
      // chat reply — the app said "here's a short pass at it" and produced
      // nothing to play.
      expect(StudioDetection.detectStudio('generate audio talking about pink '
          'flowers'), StudioType.voiceStudio);
    });

    test('music words still win over the bare "audio" fallback', () {
      for (final prompt in [
        'an audio bed for my ad',
        'a soundtrack for the opening titles',
        'write me a jingle',
      ]) {
        expect(StudioDetection.detectStudio(prompt), StudioType.musicStudio,
            reason: prompt);
      }
    });

    test('the voice route always is; the audio route depends on the words', () {
      expect(wantsSpokenAudio(ChatRoute.voice, 'anything'), isTrue);
      expect(
          wantsSpokenAudio(ChatRoute.audio, 'generate audio talking about pink '
              'flowers'),
          isTrue);
      expect(wantsSpokenAudio(ChatRoute.audio, 'an audio bed for my ad'),
          isFalse);
      expect(wantsSpokenAudio(ChatRoute.chat, 'hello'), isFalse);
    });
  });

  group('a voiceover turn with a key', () {
    test('the key is actually used and the card carries real audio', () async {
      // This used to fall off the end of the client-kind switch into the mock,
      // so a paid ElevenLabs key produced the built-in synthesizer's card and
      // was never touched.
      final (events, client) = await _run('i need a voiceover talking about '
          'pink flowers');

      expect(client.callCount, 1);
      final result =
          events.whereType<StudioResultReady>().single.result as AudioResult;
      expect(result.kind, AudioKind.voice);
      expect(result.audioBytes, isNotNull);
      expect(result.audioBytes!.length, greaterThan(1000));
    });

    test('"generate audio talking about..." gets there too', () async {
      final (events, client) =
          await _run('generate audio talking about pink flowers',
              route: ChatRoute.audio);

      expect(client.callCount, 1);
      expect(events.whereType<StudioResultReady>(), hasLength(1));
    });

    test('the script is written, not the prompt read back', () async {
      final (_, client) = await _run('i need a voiceover talking about pink '
          'flowers');

      // No text provider is keyed here, so it falls to the template — which
      // still must be a script rather than the prompt itself.
      expect(client.spokenText, isNotNull);
      expect(client.spokenText, isNot('i need a voiceover talking about pink '
          'flowers'));
    });
  });

  test('a failure says so instead of quietly handing over a fake', () async {
    final (events, client) =
        await _run('i need a voiceover about pink flowers', fail: true);

    expect(client.callCount, 1);
    final text = events.whereType<MessageDelta>().map((d) => d.chunk).join();
    expect(text.toLowerCase(), contains('synthesizer'));
    // The card still arrives — a silent turn would be worse than a synthesized
    // one.
    expect(events.whereType<StudioResultReady>(), hasLength(1));
  });

  test('with no voice key it stays the simulated card', () async {
    final (events, client) =
        await _run('i need a voiceover about pink flowers', withKey: false);

    expect(client.callCount, 0);
    expect(events.whereType<StudioResultReady>(), hasLength(1));
  });
}
