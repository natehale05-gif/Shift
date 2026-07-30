import 'speech_service.dart';

/// The no-speech fallback. No longer reached by any shipping target — web
/// uses `speech_web.dart` and everything else `speech_io.dart` — but kept as
/// the shape those two must satisfy, and as the target for a platform that
/// later turns out to have neither.
bool speechRecognitionSupported() => false;

Future<bool> ensureSpeechReady() async => false;

Stream<SpeechResult> startListening() => const Stream.empty();

void stopListening() {}

bool ttsSupported() => false;

void speak(String text) {}

/// No-op off the web: the platform engines have no gesture requirement.
void primeSpeech() {}

void stopSpeaking() {}
