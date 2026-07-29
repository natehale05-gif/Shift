import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/features/voice/live_audio_utils.dart';

void main() {
  test('downsample 48k→16k produces one sample per three inputs', () {
    final input = Float32List.fromList(List.filled(4800, 0.5));
    final pcm = downsampleFloat32ToPcm16(input: input, inputRate: 48000);
    expect(pcm.length ~/ 2, 1600);
    // 0.5 encodes near 16384.
    final data = ByteData.sublistView(pcm);
    expect(data.getInt16(0, Endian.little), closeTo(16384, 2));
  });

  test('values clamp to the PCM16 range', () {
    final input = Float32List.fromList([2.0, -2.0]);
    final pcm = downsampleFloat32ToPcm16(
        input: input, inputRate: 16000, outputRate: 16000);
    final data = ByteData.sublistView(pcm);
    expect(data.getInt16(0, Endian.little), 32767);
    expect(data.getInt16(2, Endian.little), -32767);
  });

  test('pcm16 → float32 round-trips within quantization error', () {
    final original = Float32List.fromList([0.0, 0.25, -0.75, 0.99]);
    final pcm = downsampleFloat32ToPcm16(
        input: original, inputRate: 16000, outputRate: 16000);
    final restored = pcm16BytesToFloat32(pcm);
    for (var i = 0; i < original.length; i++) {
      expect(restored[i], closeTo(original[i], 0.001));
    }
  });

  test('empty input yields empty output', () {
    expect(
      downsampleFloat32ToPcm16(input: Float32List(0), inputRate: 48000),
      isEmpty,
    );
    expect(pcm16BytesToFloat32(Uint8List(0)), isEmpty);
  });
}
