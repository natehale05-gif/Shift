import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/api_keys_store.dart';
import 'package:shift_ai/data/stores/conversation_store.dart';
import 'package:shift_ai/features/voice/voice_mode_controller.dart';
import 'package:shift_ai/providers/clients/elevenlabs_client.dart';
import 'package:shift_ai/providers/clients/provider_access.dart';
import 'package:shift_ai/turn/backends/mock_backend.dart';

/// Records how each spoken line was authorised.
class _RecordingVoice extends ElevenLabsClient {
  final List<ProviderAccess> seen = [];

  @override
  Future<Uint8List> speak({
    required ProviderAccess access,
    required String text,
    String voiceId = ElevenLabsClient.defaultVoiceId,
    String model = ElevenLabsClient.defaultModel,
  }) async {
    seen.add(access);
    return Uint8List.fromList([1, 2, 3, 4]);
  }
}

Future<VoiceModeController> _controller({
  required _RecordingVoice voice,
  String? ownKey,
  Set<String> covered = const {},
}) async {
  SharedPreferences.setMockInitialValues({});
  final persistence = PersistenceService();
  final keys = ApiKeysStore(persistence: persistence);
  await keys.load();
  if (ownKey != null) await keys.setKey('elevenlabs', ownKey);

  final managed = ManagedAccess(
    base: Uri.parse('https://p.test/functions/v1/provider-proxy/elevenlabs'),
    headers: const {'Authorization': 'Bearer session-token'},
  );

  return VoiceModeController(
    conversations: ConversationStore(
      chatService: MockChatService(),
      persistence: persistence,
    ),
    keys: keys,
    elevenLabsClient: voice,
    managedProviders: () => covered,
    managedAccess: (provider) async =>
        covered.contains(provider) ? managed : null,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // `dispose()` stops the platform speech engine, which is a plugin with
    // nothing behind it on the VM — it throws out of the async gap, after the
    // test has already passed, and reports as a failure of whatever ran next.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_tts'), (_) async => 1);
  });

  // What each of these asserts is *which credential reached the provider*,
  // which is the whole of the change. Deliberately not the return value on the
  // paths that do call out: off-web playback hands the WAV to the OS through
  // `path_provider`, which has no plugin behind it in a `flutter test` binding,
  // so `speakWithProvider` answers false after a perfectly good call. Asserting
  // the boolean there would be asserting that this machine can play audio.
  //
  // On the path that must *not* call out, the boolean is asserted, because
  // there the answer is the decision rather than the environment.

  test('voice mode speaks on the plan, with no key on the device', () async {
    // This was excluded from the membership on the grounds that it "runs
    // outside the turn pipeline and has no meter on it". That was wrong: the
    // meter is in the proxy, not in the pipeline, and `speak` is an ordinary
    // ElevenLabs POST that the proxy forwards and prices like any other.
    final voice = _RecordingVoice();
    final controller = await _controller(voice: voice, covered: {'elevenlabs'});

    await controller.speakWithProvider('hello');
    expect(voice.seen.single, isA<ManagedAccess>());
    controller.dispose();
  });

  test('the plan is spent before the member\'s own key', () async {
    // The same precedence the turn pipeline uses: they pay monthly, so it is
    // the thing that should get used.
    final voice = _RecordingVoice();
    final controller = await _controller(
      voice: voice,
      ownKey: 'their-own-key',
      covered: {'elevenlabs'},
    );

    await controller.speakWithProvider('hello');
    expect(voice.seen.single, isA<ManagedAccess>());
    controller.dispose();
  });

  test('their own key takes over when the plan cannot pay', () async {
    // Running out of ceiling should degrade to their key rather than drop them
    // back to the platform's robot voice mid-sentence.
    final voice = _RecordingVoice();
    final controller =
        await _controller(voice: voice, ownKey: 'their-own-key');

    await controller.speakWithProvider('hello');
    expect((voice.seen.single as DirectKey).key, 'their-own-key');
    controller.dispose();
  });

  test('no plan and no key falls back to the platform voice', () async {
    // Not an error — the device's own speech engine is the fallback, and it
    // must not be reached by way of a call with an empty credential.
    final voice = _RecordingVoice();
    final controller = await _controller(voice: voice);

    expect(await controller.speakWithProvider('hello'), isFalse);
    expect(voice.seen, isEmpty);
    controller.dispose();
  });
}
