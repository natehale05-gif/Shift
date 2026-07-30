import 'speech_io.dart' if (dart.library.html) 'speech_web.dart' as impl;

/// One recognition update: the transcript so far and whether it's final.
class SpeechResult {
  final String transcript;
  final bool isFinal;

  const SpeechResult({required this.transcript, required this.isFinal});
}

/// Speech-to-text, wherever the platform offers it.
///
/// In a browser that is the Web Speech API (Chrome/Edge/Safari; not Firefox).
/// Off-web it is the platform recognizer: Android, iOS and macOS have one,
/// Linux does not, Windows is partial. [isSupported] gates the mic button, and
/// [ensureReady] is what actually asks the device — the synchronous getter
/// exists because a button has to render before an async probe can finish.
class SpeechService {
  SpeechService._();

  static bool get isSupported => impl.speechRecognitionSupported();

  /// Asks the platform whether it can listen, initializing it if needed.
  /// Returns false when there is no recognizer or permission was refused.
  static Future<bool> ensureReady() => impl.ensureSpeechReady();

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

  /// Unlocks speech output. Call from the tap that opens voice mode, before
  /// anything is awaited — see the web implementation for why.
  static void prime() => impl.primeSpeech();

  static void stopSpeaking() => impl.stopSpeaking();
}
