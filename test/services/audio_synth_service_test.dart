import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/services/audio_synth_service.dart';

void main() {
  group('AudioSynthService.synthesizeWav', () {
    test('produces a valid RIFF/WAVE header', () {
      final bytes = AudioSynthService.synthesizeWav(
        seed: 1,
        durationSec: 1,
        bpm: 100,
        speechLike: false,
      );

      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');
    });

    test('data size matches sample rate * duration * 2 bytes (mono 16-bit)', () {
      const durationSec = 2;
      final bytes = AudioSynthService.synthesizeWav(
        seed: 42,
        durationSec: durationSec,
        bpm: 120,
        speechLike: false,
      );

      final expectedDataBytes = AudioSynthService.sampleRate * durationSec * 2;
      expect(bytes.length, 44 + expectedDataBytes);
    });

    test('is deterministic for the same seed', () {
      final a = AudioSynthService.synthesizeWav(seed: 7, durationSec: 1, bpm: 90, speechLike: true);
      final b = AudioSynthService.synthesizeWav(seed: 7, durationSec: 1, bpm: 90, speechLike: true);
      expect(a, equals(b));
    });

    test('differs for different seeds', () {
      final a = AudioSynthService.synthesizeWav(seed: 1, durationSec: 1, bpm: 90, speechLike: true);
      final b = AudioSynthService.synthesizeWav(seed: 2, durationSec: 1, bpm: 90, speechLike: true);
      expect(a, isNot(equals(b)));
    });

    test('samples stay within 16-bit PCM range', () {
      final bytes = AudioSynthService.synthesizeWav(
        seed: 5,
        durationSec: 1,
        bpm: 140,
        speechLike: false,
      );
      final data = bytes.sublist(44);
      final samples = data.buffer.asInt16List(data.offsetInBytes, data.length ~/ 2);
      for (final s in samples) {
        expect(s, inInclusiveRange(-32768, 32767));
      }
    });
  });
}
