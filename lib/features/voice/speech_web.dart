// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;

import 'speech_service.dart';

html.SpeechRecognition? _active;

bool speechRecognitionSupported() => html.SpeechRecognition.supported;

Stream<SpeechResult> startListening() {
  stopListening();
  final controller = StreamController<SpeechResult>();
  final recognition = html.SpeechRecognition()
    ..continuous = false
    ..interimResults = true
    ..lang = 'en-US';
  _active = recognition;

  recognition.onResult.listen((event) {
    final results = event.results;
    if (results == null || results.isEmpty) return;
    final buffer = StringBuffer();
    var isFinal = true;
    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      buffer.write(result.item(0).transcript ?? '');
      if (!(result.isFinal ?? false)) isFinal = false;
    }
    if (!controller.isClosed) {
      controller.add(
        SpeechResult(transcript: buffer.toString(), isFinal: isFinal),
      );
    }
  });
  recognition.onError.listen((_) {
    if (!controller.isClosed) controller.close();
  });
  recognition.onEnd.listen((_) {
    if (!controller.isClosed) controller.close();
    if (identical(_active, recognition)) _active = null;
  });

  recognition.start();
  controller.onCancel = () => recognition.abort();
  return controller.stream;
}

void stopListening() {
  _active?.stop();
  _active = null;
}

bool ttsSupported() => html.window.speechSynthesis != null;

void speak(String text) {
  final synthesis = html.window.speechSynthesis;
  if (synthesis == null) return;
  synthesis.cancel();
  synthesis.speak(html.SpeechSynthesisUtterance(text));
}

void stopSpeaking() {
  html.window.speechSynthesis?.cancel();
}

/// The browser answers synchronously, so there is nothing to initialize —
/// this exists to match the shape the off-web implementation needs.
Future<bool> ensureSpeechReady() async => speechRecognitionSupported();
