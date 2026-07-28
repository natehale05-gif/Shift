import 'speech_service.dart';

/// Non-web fallback (compiled for the `flutter test` VM target): speech
/// APIs only exist in the browser.
bool speechRecognitionSupported() => false;

Stream<SpeechResult> startListening() => const Stream.empty();

void stopListening() {}

bool ttsSupported() => false;

void speak(String text) {}

void stopSpeaking() {}
