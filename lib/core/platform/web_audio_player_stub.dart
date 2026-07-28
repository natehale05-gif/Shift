import 'dart:typed_data';

import 'web_audio_player.dart';

WebAudioPlayer createPlayer(Uint8List bytes) => _StubAudioPlayer();

/// Inert stand-in used only when compiling for non-web targets. This app
/// ships exclusively to web, so this is never exercised at runtime.
class _StubAudioPlayer implements WebAudioPlayer {
  @override
  bool get isPlaying => false;

  @override
  double get progress => 0;

  @override
  Stream<void> get onProgress => const Stream.empty();

  @override
  Stream<void> get onEnded => const Stream.empty();

  @override
  Future<void> play() async {}

  @override
  void pause() {}

  @override
  void restart() {}

  @override
  void dispose() {}
}
