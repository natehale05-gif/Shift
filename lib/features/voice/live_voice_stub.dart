import 'live_voice_controller.dart';

/// Non-web fallback (compiled for the `flutter test` VM target).
bool liveVoiceSupported() => false;

Stream<LiveVoiceState> startLiveVoice(String apiKey) => Stream.value(
      const LiveVoiceState(
        LiveVoicePhase.error,
        'Live voice runs in the browser build.',
      ),
    );

void setLiveVoiceMuted(bool muted) {}

void endLiveVoice() {}
