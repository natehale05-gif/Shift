
/// Synthesizes a short, deterministic mono WAV file from a seed — a
/// procedurally generated tone sequence standing in for real AI-generated
/// music or voice, in keeping with the rest of this app's mock studios.
/// Deterministic (same seed -> same bytes) so nothing needs to be persisted:
/// [AudioResult] only stores the seed/params, and both playback and
/// download regenerate the same audio on demand.
library;
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class AudioSynthService {
  AudioSynthService._();

  static const int sampleRate = 22050;

  static Uint8List synthesizeWav({
    required int seed,
    required int durationSec,
    required int bpm,
    required bool speechLike,
  }) {
    final random = Random(seed);
    final totalSamples = sampleRate * durationSec;
    final samples = Int16List(totalSamples);

    // A narrow, chattery set of tones for "voice" results; a pentatonic-ish
    // major scale for "music" results.
    final scale = speechLike
        ? const [220.0, 246.94, 261.63, 293.66, 329.63]
        : const [261.63, 293.66, 329.63, 392.00, 440.00, 523.25];

    final beatSeconds = speechLike ? 0.14 : (60.0 / bpm.clamp(40, 220));
    final samplesPerNote = max(1, (sampleRate * beatSeconds).round());

    var index = 0;
    while (index < totalSamples) {
      final freq = scale[random.nextInt(scale.length)];
      final noteLength = min(samplesPerNote, totalSamples - index);
      for (var i = 0; i < noteLength; i++) {
        final t = i / sampleRate;
        final envelope = _envelope(i, noteLength);
        final value = sin(2 * pi * freq * t) * envelope * 0.3;
        samples[index + i] = (value * 32767).round().clamp(-32768, 32767);
      }
      index += noteLength;
    }

    return _wavBytes(samples);
  }

  /// Linear attack/release envelope so adjacent notes don't produce audible
  /// clicks at the sample boundary.
  static double _envelope(int i, int total) {
    final attack = max(1, (total * 0.08).round());
    final release = max(1, (total * 0.25).round());
    if (i < attack) return i / attack;
    if (i > total - release) return (total - i) / release;
    return 1.0;
  }

  /// Wraps raw little-endian 16-bit mono PCM in a WAV container.
  ///
  /// A provider that speaks (ElevenLabs) can return PCM, and everything
  /// downstream here — the card's player, the download button, the off-web
  /// file handoff — already understands WAV. Wrapping is a header; transcoding
  /// MP3 would be a decoder.
  static Uint8List wavFromPcm16(Uint8List pcm, {int sampleRate = 44100}) {
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcm.lengthInBytes;

    final header = BytesBuilder()
      ..add(ascii.encode('RIFF'))
      ..add(_uint32(36 + dataSize))
      ..add(ascii.encode('WAVE'))
      ..add(ascii.encode('fmt '))
      ..add(_uint32(16))
      ..add(_uint16(1))
      ..add(_uint16(channels))
      ..add(_uint32(sampleRate))
      ..add(_uint32(byteRate))
      ..add(_uint16(blockAlign))
      ..add(_uint16(bitsPerSample))
      ..add(ascii.encode('data'))
      ..add(_uint32(dataSize));

    return (BytesBuilder()
          ..add(header.toBytes())
          ..add(pcm))
        .toBytes();
  }

  static Uint8List _wavBytes(Int16List samples) {
    const channels = 1;
    const bitsPerSample = 16;
    const byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    const blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = samples.lengthInBytes;

    final header = BytesBuilder()
      ..add(ascii.encode('RIFF'))
      ..add(_uint32(36 + dataSize))
      ..add(ascii.encode('WAVE'))
      ..add(ascii.encode('fmt '))
      ..add(_uint32(16))
      ..add(_uint16(1))
      ..add(_uint16(channels))
      ..add(_uint32(sampleRate))
      ..add(_uint32(byteRate))
      ..add(_uint16(blockAlign))
      ..add(_uint16(bitsPerSample))
      ..add(ascii.encode('data'))
      ..add(_uint32(dataSize));

    return (BytesBuilder()
          ..add(header.toBytes())
          ..add(samples.buffer.asUint8List(samples.offsetInBytes, dataSize)))
        .toBytes();
  }

  static Uint8List _uint32(int value) =>
      (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();

  static Uint8List _uint16(int value) =>
      (ByteData(2)..setUint16(0, value, Endian.little)).buffer.asUint8List();
}
