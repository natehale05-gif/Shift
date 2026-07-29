import 'speech_stub.dart' if (dart.library.html) 'speech_web.dart' as impl;

/// One recognition update: the transcript so far and whether it's final.
class SpeechResult {
  final String transcript;
  final bool isFinal;

  const SpeechResult({required this.transcript, required this.isFinal});
}

/// Browser speech-to-text (Web Speech API). Chrome/Edge/Safari support it;
/// Firefox doesn't — [isSupported] gates the mic button's behavior.
class SpeechService {
  SpeechService._();

  static bool get isSupported => impl.speechRecognitionSupported();

  /// Starts dictation; emits interim and final transcripts until the user
  /// stops speaking or [stop] is called (the stream then closes).
  static Stream<SpeechResult> listen() => impl.startListening();

  static void stop() => impl.stopListening();
}

/// Browser text-to-speech (speechSynthesis) for reading replies aloud.
class TtsService {
  TtsService._();

  static bool get isSupported => impl.ttsSupported();

  static void speak(String text) => impl.speak(text);

  static void stopSpeaking() => impl.stopSpeaking();
}
