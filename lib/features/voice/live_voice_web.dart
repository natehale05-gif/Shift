// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import '../../providers/clients/gemini_api_config.dart';
import 'live_audio_utils.dart';
import 'live_voice_controller.dart';

_LiveSession? _session;

bool liveVoiceSupported() => html.window.navigator.mediaDevices != null;

Stream<LiveVoiceState> startLiveVoice(String apiKey) {
  endLiveVoice();
  final session = _LiveSession(apiKey);
  _session = session;
  return session.start();
}

void setLiveVoiceMuted(bool muted) => _session?.muted = muted;

void endLiveVoice() {
  _session?.dispose();
  _session = null;
}

/// One realtime session: WebSocket + mic capture (ScriptProcessor,
/// downsampled to 16kHz PCM16) + scheduled playback of streamed 24kHz PCM.
/// Web Audio is driven through js_util interop — `dart:web_audio` no longer
/// ships with the SDK.
class _LiveSession {
  final String apiKey;
  final _states = StreamController<LiveVoiceState>();

  html.WebSocket? _socket;
  Object? _audioContext;
  Object? _processor;
  html.MediaStream? _micStream;

  bool muted = false;
  bool _setupComplete = false;
  double _playhead = 0;

  _LiveSession(this.apiKey);

  Stream<LiveVoiceState> start() {
    _run();
    return _states.stream;
  }

  Future<void> _run() async {
    _emit(const LiveVoiceState(LiveVoicePhase.connecting));
    try {
      _micStream = await html.window.navigator.mediaDevices!
          .getUserMedia({'audio': true});
    } catch (e) {
      _emit(LiveVoiceState(
          LiveVoicePhase.error, 'Microphone permission denied. ($e)'));
      await _states.close();
      return;
    }

    final socket =
        html.WebSocket(GeminiApiConfig.liveEndpoint(apiKey).toString());
    _socket = socket;
    socket.binaryType = 'arraybuffer';

    socket.onOpen.listen((_) {
      // Handshake: declare the model and ask for audio replies.
      socket.send(jsonEncode({
        'setup': {
          'model': 'models/${GeminiApiConfig.liveModel}',
          'generationConfig': {
            'responseModalities': ['AUDIO'],
          },
        },
      }));
    });

    socket.onMessage.listen(_onSocketMessage);
    socket.onError.listen((_) {
      _emit(const LiveVoiceState(
          LiveVoicePhase.error,
          'WebSocket error — the Live API endpoint or model id may have '
          'changed (see gemini_api_config.dart), or the key lacks Live '
          'access.'));
    });
    socket.onClose.listen((event) {
      if (!_states.isClosed) {
        _emit(LiveVoiceState(
          event.code == 1000 ? LiveVoicePhase.closed : LiveVoicePhase.error,
          event.code == 1000
              ? null
              : 'Connection closed (${event.code}): ${event.reason}',
        ));
        _states.close();
      }
    });
  }

  Future<void> _onSocketMessage(html.MessageEvent event) async {
    final raw = event.data;
    String text;
    if (raw is String) {
      text = raw;
    } else if (raw is ByteBuffer) {
      text = utf8.decode(raw.asUint8List());
    } else if (raw is html.Blob) {
      text = await _blobText(raw);
    } else {
      return;
    }

    Map<String, dynamic> message;
    try {
      message = jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return;
    }

    if (message.containsKey('setupComplete')) {
      _setupComplete = true;
      _startMicCapture();
      _emit(const LiveVoiceState(LiveVoicePhase.ready));
      return;
    }

    final serverContent = message['serverContent'] as Map<String, dynamic>?;
    if (serverContent == null) return;

    if (serverContent['interrupted'] == true) {
      // Barge-in: drop queued audio and listen again.
      _playhead = 0;
      _emit(const LiveVoiceState(LiveVoicePhase.ready));
      return;
    }

    final parts = ((serverContent['modelTurn']
            as Map<String, dynamic>?)?['parts'] as List<dynamic>?) ??
        const [];
    for (final part in parts) {
      final inline = (part as Map<String, dynamic>)['inlineData']
          as Map<String, dynamic>?;
      final data = inline?['data'] as String?;
      if (data != null) {
        _emit(const LiveVoiceState(LiveVoicePhase.speaking));
        _playPcm24k(base64Decode(data));
      }
    }
    if (serverContent['turnComplete'] == true) {
      _emit(const LiveVoiceState(LiveVoicePhase.ready));
    }
  }

  Object? _newAudioContext() {
    final ctor = js_util.getProperty(html.window, 'AudioContext') ??
        js_util.getProperty(html.window, 'webkitAudioContext');
    if (ctor == null) return null;
    return js_util.callConstructor(ctor as Object, const []);
  }

  void _startMicCapture() {
    final context = _newAudioContext();
    if (context == null) {
      _emit(const LiveVoiceState(
          LiveVoicePhase.error, 'Web Audio is unavailable in this browser.'));
      return;
    }
    _audioContext = context;
    final inputRate =
        (js_util.getProperty(context, 'sampleRate') as num? ?? 48000)
            .round();
    final source = js_util
        .callMethod(context, 'createMediaStreamSource', [_micStream]);
    // ScriptProcessor is deprecated but universally supported; fine for an
    // experimental feature and avoids shipping a separate worklet file.
    final processor = js_util
        .callMethod(context, 'createScriptProcessor', [4096, 1, 1]);
    _processor = processor;

    js_util.setProperty(
      processor as Object,
      'onaudioprocess',
      js_util.allowInterop((Object event) {
        if (muted || !_setupComplete) return;
        final socket = _socket;
        if (socket == null || socket.readyState != html.WebSocket.OPEN) {
          return;
        }
        final inputBuffer = js_util.getProperty(event, 'inputBuffer');
        final samples = js_util
            .callMethod(inputBuffer as Object, 'getChannelData', [0]);
        if (samples is! Float32List) return;
        final pcm =
            downsampleFloat32ToPcm16(input: samples, inputRate: inputRate);
        socket.send(jsonEncode({
          'realtimeInput': {
            'audio': {
              'data': base64Encode(pcm),
              'mimeType': 'audio/pcm;rate=16000',
            },
          },
        }));
      }),
    );

    final destination = js_util.getProperty(context, 'destination');
    js_util.callMethod(source as Object, 'connect', [processor]);
    // A ScriptProcessor only fires when routed to a destination; go through
    // a zero-gain node so the mic isn't audible locally.
    final silence = js_util.callMethod(context, 'createGain', const []);
    js_util.setProperty(
        js_util.getProperty(silence as Object, 'gain') as Object,
        'value',
        0);
    js_util.callMethod(processor, 'connect', [silence]);
    js_util.callMethod(silence, 'connect', [destination]);
  }

  void _playPcm24k(Uint8List pcmBytes) {
    final context = _audioContext;
    if (context == null) return;
    final samples = pcm16BytesToFloat32(pcmBytes);
    if (samples.isEmpty) return;

    final buffer = js_util
        .callMethod(context, 'createBuffer', [1, samples.length, 24000]);
    js_util.callMethod(buffer as Object, 'copyToChannel', [samples, 0]);
    final source =
        js_util.callMethod(context, 'createBufferSource', const []);
    js_util.setProperty(source as Object, 'buffer', buffer);
    js_util.callMethod(source, 'connect',
        [js_util.getProperty(context, 'destination')]);
    final now =
        (js_util.getProperty(context, 'currentTime') as num? ?? 0)
            .toDouble();
    if (_playhead < now) _playhead = now;
    js_util.callMethod(source, 'start', [_playhead]);
    _playhead += samples.length / 24000;
  }

  void _emit(LiveVoiceState state) {
    if (!_states.isClosed) _states.add(state);
  }

  void dispose() {
    final processor = _processor;
    if (processor != null) {
      js_util.setProperty(processor, 'onaudioprocess', null);
      js_util.callMethod(processor, 'disconnect', const []);
    }
    _micStream?.getTracks().forEach((track) => track.stop());
    final context = _audioContext;
    if (context != null) {
      js_util.callMethod(context, 'close', const []);
    }
    _socket?.close(1000);
    if (!_states.isClosed) _states.close();
  }
}

Future<String> _blobText(html.Blob blob) {
  final completer = Completer<String>();
  final reader = html.FileReader();
  reader.onLoadEnd.listen((_) {
    completer.complete(reader.result as String? ?? '');
  });
  reader.readAsText(blob);
  return completer.future;
}
