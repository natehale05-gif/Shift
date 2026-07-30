import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/features/voice/speech_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // This suite used to assert that speech was inert off-web. That was the
  // defect, not the contract: the whole feature was a browser API behind a
  // conditional import, so the mic button in the downloaded app did nothing at
  // all. Off-web now goes to the platform recognizer.
  //
  // On the test VM there is no platform behind the plugin channels, so what is
  // checkable here is that the facade degrades instead of throwing. Whether a
  // device can actually listen is answered by the device.

  test('a platform with no recognizer reports that, rather than throwing',
      () async {
    // No plugin is registered under `flutter test`, so initialization fails —
    // which is exactly the Linux case, and it must be a false, not a crash.
    expect(await SpeechService.ensureReady(), isFalse);
    expect(SpeechService.isSupported, isFalse,
        reason: 'the probe has run, so the optimistic default is spent');
  });

  test('listening with no recognizer closes instead of hanging', () async {
    // A stream that never closes would leave voice mode stuck on "Listening"
    // forever with no way to tell that nothing is coming.
    expect(await SpeechService.listen().toList(), isEmpty);
  });

  test('the no-op paths do not throw', () {
    expect(SpeechService.stop, returnsNormally);
    expect(() => TtsService.speak('hello'), returnsNormally);
    expect(TtsService.stopSpeaking, returnsNormally);
  });
}
