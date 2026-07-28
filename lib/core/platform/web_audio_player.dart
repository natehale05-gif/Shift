import 'dart:typed_data';

import 'web_audio_player_stub.dart'
    if (dart.library.html) 'web_audio_player_web.dart' as impl;

/// Thin cross-platform wrapper over browser audio playback. The real
/// implementation (`web_audio_player_web.dart`, an `html.AudioElement`
/// backed by a Blob URL) only compiles in for the web target; the stub
/// keeps this interface (and anything that references it) compiling under
/// `flutter test`'s VM target, where `dart:html` doesn't exist — this app
/// only ever ships to web, so the stub is never exercised at runtime.
abstract class WebAudioPlayer {
  bool get isPlaying;

  /// Playback position as a 0..1 fraction of duration (0 if unknown).
  double get progress;

  Stream<void> get onProgress;
  Stream<void> get onEnded;

  Future<void> play();
  void pause();
  void restart();
  void dispose();

  static WebAudioPlayer fromWav(Uint8List bytes) => impl.createPlayer(bytes);
}
