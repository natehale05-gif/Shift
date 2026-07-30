import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'speech_service.dart';

/// Off-web speech, so the mic button in a downloaded app does something.
///
/// It used to be inert here — the whole feature was a browser API behind a
/// conditional import, and the stub was written when this app shipped to web
/// only. On a phone that meant tapping the mic and watching nothing happen.
///
/// Platform reality, since it is not uniform and pretending otherwise is how
/// the previous version misled people: `speech_to_text` covers Android, iOS
/// and macOS. Windows support is partial and Linux has none, so
/// [speechRecognitionSupported] answers from the plugin's own initialization
/// rather than from a hardcoded list — a platform that cannot listen reports
/// that it cannot, and the composer says so.
final _recognizer = stt.SpeechToText();
final _tts = FlutterTts();

bool _initialized = false;
bool _available = false;

/// Whether the plugin came up on this device.
///
/// Synchronous by necessity — the button has to render before an async probe
/// could finish — so this reports the last known answer and
/// [ensureSpeechReady] is what actually asks. It answers optimistically until
/// the first probe resolves, because rendering a permanently disabled mic on a
/// device that supports dictation is the worse error.
bool speechRecognitionSupported() => !_initialized || _available;

/// Initializes recognition and returns whether it can be used. Safe to call
/// repeatedly; the plugin is only initialized once.
Future<bool> ensureSpeechReady() async {
  if (_initialized) return _available;
  try {
    _available = await _recognizer.initialize(
      onError: (_) {},
      onStatus: (_) {},
    );
  } catch (_) {
    _available = false;
  }
  _initialized = true;
  return _available;
}

StreamController<SpeechResult>? _controller;

Stream<SpeechResult> startListening() {
  final controller = StreamController<SpeechResult>();
  _controller = controller;

  Future<void> begin() async {
    if (!await ensureSpeechReady()) {
      await controller.close();
      return;
    }
    await _recognizer.listen(
      onResult: (result) {
        if (controller.isClosed) return;
        controller.add(SpeechResult(
          transcript: result.recognizedWords,
          isFinal: result.finalResult,
        ));
        // The platform recognizers stop themselves on a final result, so the
        // stream has to close too or the caller waits forever for a `done`
        // that is never coming.
        if (result.finalResult) controller.close();
      },
      listenOptions: stt.SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        // Long enough to finish a sentence, and to tolerate a pause
        // mid-thought without cutting someone off.
        listenFor: const Duration(seconds: 45),
        pauseFor: const Duration(seconds: 3),
      ),
    );
  }

  begin();
  controller.onCancel = () => _recognizer.stop();
  return controller.stream;
}

void stopListening() {
  _recognizer.stop();
  final controller = _controller;
  _controller = null;
  if (controller != null && !controller.isClosed) controller.close();
}

/// System text-to-speech. Available on every platform this app ships to, so
/// unlike recognition it is not gated.
bool ttsSupported() => true;

/// No-op: only Safari gates speech behind a user gesture.
void primeSpeech() {}

void speak(String text) {
  if (text.trim().isEmpty) return;
  _tts.speak(text);
}

void stopSpeaking() {
  _tts.stop();
}
