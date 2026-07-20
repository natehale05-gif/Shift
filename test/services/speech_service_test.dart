import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/services/speech/speech_service.dart';

void main() {
  test('VM stubs report unsupported and stay inert (no dart:html leaks)',
      () async {
    expect(SpeechService.isSupported, isFalse);
    expect(TtsService.isSupported, isFalse);
    expect(await SpeechService.listen().toList(), isEmpty);
    // No-ops must not throw off-web.
    SpeechService.stop();
    TtsService.speak('hello');
    TtsService.stopSpeaking();
  });
}
