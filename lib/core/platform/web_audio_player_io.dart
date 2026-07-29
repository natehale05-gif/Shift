import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'open_url.dart';
import 'web_audio_player.dart';

WebAudioPlayer createPlayer(Uint8List bytes) => _SystemAudioPlayer(bytes);

/// Off-web playback: write the WAV and hand it to whatever the OS uses for
/// audio, the same move the artifact preview makes for HTML.
///
/// Inline playback with a working transport would need an audio package, and
/// on Linux that means a GStreamer runtime the tar.gz cannot guarantee. It was
/// deliberately not added here because this environment has no audio device or
/// display, so the claim "inline playback works" could not have been verified
/// on any of the four targets — and an inline player that silently fails is
/// worse than a button that opens the file in a player the user already has.
///
/// [isPlaying] and [progress] stay inert rather than pretending to track a
/// process in another application; the card's play button still does something
/// real, which the previous stub did not.
class _SystemAudioPlayer implements WebAudioPlayer {
  final Uint8List _bytes;
  _SystemAudioPlayer(this._bytes);

  @override
  bool get isPlaying => false;

  @override
  double get progress => 0;

  @override
  Stream<void> get onProgress => const Stream.empty();

  @override
  Stream<void> get onEnded => const Stream.empty();

  @override
  Future<void> play() async {
    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/shift_audio_$stamp.wav');
    await file.writeAsBytes(_bytes, flush: true);
    openUrl(file.uri.toString());
  }

  @override
  void pause() {}

  @override
  void restart() {}

  @override
  void dispose() {}
}
