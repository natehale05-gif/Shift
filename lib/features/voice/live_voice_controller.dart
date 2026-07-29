import 'live_voice_stub.dart' if (dart.library.html) 'live_voice_web.dart'
    as impl;

/// Where a Live voice session currently is. [detail] carries raw error
/// text when [LiveVoicePhase.error] — deliberately unfiltered, since the
/// Live API moves fast and raw messages are what make drift diagnosable.
enum LiveVoicePhase { connecting, ready, speaking, error, closed }

class LiveVoiceState {
  final LiveVoicePhase phase;
  final String? detail;

  const LiveVoiceState(this.phase, [this.detail]);
}

/// Realtime voice conversation over the Gemini Live API (EXPERIMENTAL):
/// browser mic → PCM16@16kHz over WebSocket → streamed PCM16@24kHz reply
/// audio played back as it arrives. Browser-only; requires a Google key.
class LiveVoiceController {
  static bool get isSupported => impl.liveVoiceSupported();

  /// Opens the session (WebSocket + mic capture + playback). The stream
  /// reports phase changes and closes when the session ends.
  static Stream<LiveVoiceState> start(String apiKey) =>
      impl.startLiveVoice(apiKey);

  static void setMuted(bool muted) => impl.setLiveVoiceMuted(muted);

  static void end() => impl.endLiveVoice();
}
