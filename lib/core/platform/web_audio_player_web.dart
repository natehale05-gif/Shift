// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'web_audio_player.dart';

WebAudioPlayer createPlayer(Uint8List bytes) => _HtmlAudioPlayer(bytes);

class _HtmlAudioPlayer implements WebAudioPlayer {
  late final String _blobUrl;
  late final html.AudioElement _audio;
  final _progressController = StreamController<void>.broadcast();
  final _endedController = StreamController<void>.broadcast();
  bool _playing = false;

  _HtmlAudioPlayer(Uint8List bytes) {
    final blob = html.Blob([bytes], 'audio/wav');
    _blobUrl = html.Url.createObjectUrlFromBlob(blob);
    _audio = html.AudioElement(_blobUrl);
    _audio.onTimeUpdate.listen((_) => _progressController.add(null));
    _audio.onEnded.listen((_) {
      _playing = false;
      _endedController.add(null);
    });
  }

  @override
  bool get isPlaying => _playing;

  @override
  double get progress {
    final duration = _audio.duration;
    if (!duration.isFinite || duration <= 0) return 0;
    return (_audio.currentTime / duration).clamp(0, 1);
  }

  @override
  Stream<void> get onProgress => _progressController.stream;

  @override
  Stream<void> get onEnded => _endedController.stream;

  @override
  Future<void> play() async {
    await _audio.play();
    _playing = true;
  }

  @override
  void pause() {
    _audio.pause();
    _playing = false;
  }

  @override
  void restart() {
    _audio.currentTime = 0;
  }

  @override
  void dispose() {
    _audio.pause();
    html.Url.revokeObjectUrl(_blobUrl);
    _progressController.close();
    _endedController.close();
  }
}
