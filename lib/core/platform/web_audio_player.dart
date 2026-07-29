import 'dart:typed_data';

import 'web_audio_player_io.dart'
    if (dart.library.html) 'web_audio_player_web.dart' as impl;

/// Thin cross-platform wrapper over audio playback. On the web an
/// `html.AudioElement` backed by a Blob URL plays inline with a live
/// transport; off-web the WAV is written out and handed to the system player
/// (see `web_audio_player_io.dart` for why inline playback was not adopted
/// there).
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
