import 'dart:math';
import 'dart:typed_data';

/// Pure PCM helpers for the Live voice pipeline (mic Float32 at the
/// browser's native rate → PCM16 @16kHz up; PCM16 @24kHz → Float32 down).
/// Kept dart:html-free so they're unit-testable on the VM.

/// Downsamples mono Float32 samples from [inputRate] to [outputRate] (simple
/// decimation with averaging) and encodes little-endian PCM16 bytes.
Uint8List downsampleFloat32ToPcm16({
  required Float32List input,
  required int inputRate,
  int outputRate = 16000,
}) {
  if (input.isEmpty) return Uint8List(0);
  final ratio = inputRate / outputRate;
  final outputLength = (input.length / ratio).floor();
  final output = ByteData(outputLength * 2);
  for (var i = 0; i < outputLength; i++) {
    final start = (i * ratio).floor();
    final end = min(((i + 1) * ratio).floor(), input.length);
    var sum = 0.0;
    var count = 0;
    for (var j = start; j < end; j++) {
      sum += input[j];
      count++;
    }
    final sample = count == 0 ? 0.0 : sum / count;
    final clamped = sample.clamp(-1.0, 1.0);
    output.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
  }
  return output.buffer.asUint8List();
}

/// Decodes little-endian PCM16 bytes into Float32 samples in [-1, 1].
Float32List pcm16BytesToFloat32(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final sampleCount = bytes.length ~/ 2;
  final output = Float32List(sampleCount);
  for (var i = 0; i < sampleCount; i++) {
    output[i] = data.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return output;
}
