import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/chat_message.dart';
import '../../data/stores/conversation_store.dart';
import 'speech_service.dart';
import '../studios/media/audio_synth_service.dart';
import '../../providers/clients/elevenlabs_client.dart';
import '../../providers/clients/provider_access.dart';
import '../../data/stores/api_keys_store.dart';
import '../../core/platform/web_audio_player.dart';

/// Where a hands-free turn is in its cycle.
enum VoicePhase {
  /// Waiting for the microphone, or for permission.
  starting,

  /// The microphone is open.
  listening,

  /// The reply is being generated.
  thinking,

  /// The reply is being read out.
  speaking,

  /// Stopped, either by the user or by a failure.
  idle,
}

/// Hands-free conversation: listen, send, speak the reply, listen again.
///
/// Deliberately built on the ordinary chat path rather than on a realtime
/// audio API. Two reasons. It works with whichever provider the user already
/// has a key for, instead of only the one vendor with a realtime endpoint —
/// which is the same gap that left Gemini-only users unable to build a page.
/// And every spoken turn lands in the transcript as a normal message, so a
/// conversation started by voice can be continued by typing, exported, and
/// searched like any other.
///
/// The cost is that it is turn-based: it cannot be interrupted mid-sentence
/// the way a realtime API can. Stopping is a button, not a barge-in.
class VoiceModeController extends ChangeNotifier {
  final ConversationStore conversations;

  /// Keys and a voice client, when the app has them. Voice mode falls back to
  /// the platform's own speech engine without them.
  final ApiKeysStore? keys;
  final ElevenLabsClient _elevenLabs;

  /// The providers a membership currently pays for, and how to pay with it.
  ///
  /// The same two closures the turn pipeline takes, for the same reason: this
  /// is a real ElevenLabs call over ordinary HTTP, so the proxy forwards and
  /// meters it exactly as it does a voiceover inside a turn. It was left out
  /// of the membership on the grounds that it "runs outside the turn pipeline
  /// and has no meter on it" — which was wrong. The meter is in the proxy, not
  /// in the pipeline, and every call the proxy forwards is counted.
  final Set<String> Function() managedProviders;
  final Future<ProviderAccess?> Function(String provider)? managedAccess;

  VoiceModeController({
    required this.conversations,
    this.keys,
    ElevenLabsClient? elevenLabsClient,
    Set<String> Function()? managedProviders,
    this.managedAccess,
  })  : _elevenLabs = elevenLabsClient ?? ElevenLabsClient(),
        managedProviders = managedProviders ?? _none;

  static Set<String> _none() => const {};

  WebAudioPlayer? _player;
  StreamSubscription<void>? _playerEnded;

  VoicePhase phase = VoicePhase.idle;

  /// What has been heard so far this turn, shown live so the user can tell
  /// whether the microphone is actually picking them up.
  String heard = '';

  /// Set when the loop stops for a reason worth showing.
  String? problem;

  StreamSubscription<SpeechResult>? _speech;
  VoidCallback? _storeListener;
  bool _running = false;
  bool _awaitingReply = false;

  /// The message being spoken, so a reply is never read out twice.
  String? _spokenMessageId;

  bool get isRunning => _running;

  Future<void> start() async {
    if (_running) return;
    _running = true;
    problem = null;

    // Before anything is awaited. This runs inside the tap that opened voice
    // mode, which is the only moment Safari will let speech be unlocked — and
    // the reply is spoken from an async callback long after.
    TtsService.prime();

    _setPhase(VoicePhase.starting);

    if (!await SpeechService.ensureReady()) {
      problem = 'This device has no speech recognition available, or '
          'microphone access was declined.';
      _running = false;
      _setPhase(VoicePhase.idle);
      return;
    }

    _storeListener = _onStoreChanged;
    conversations.addListener(_storeListener!);
    _listen();
  }

  void stop() {
    _running = false;
    _awaitingReply = false;
    _speech?.cancel();
    _speech = null;
    SpeechService.stop();
    TtsService.stopSpeaking();
    _playerEnded?.cancel();
    _playerEnded = null;
    _player?.dispose();
    _player = null;
    if (_storeListener != null) {
      conversations.removeListener(_storeListener!);
      _storeListener = null;
    }
    _setPhase(VoicePhase.idle);
  }

  void _listen() {
    if (!_running) return;
    heard = '';
    _setPhase(VoicePhase.listening);
    _speech = SpeechService.listen().listen(
      (result) {
        heard = result.transcript;
        notifyListeners();
        if (result.isFinal) _send(result.transcript);
      },
      onDone: () {
        // A recognizer that hears nothing closes without a final result.
        // Restarting rather than stopping is what makes this hands-free: a
        // pause in the conversation should not end the session.
        if (_running && phase == VoicePhase.listening) _listen();
      },
      onError: (_) {
        if (_running) _listen();
      },
    );
  }

  void _send(String text) {
    _speech?.cancel();
    _speech = null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      _listen();
      return;
    }
    if (conversations.current == null) {
      conversations.startNewConversation();
    }
    _awaitingReply = true;
    _setPhase(VoicePhase.thinking);
    conversations.sendMessage(trimmed);
  }

  void _onStoreChanged() {
    if (!_running || !_awaitingReply) return;
    final messages = conversations.current?.messages;
    if (messages == null || messages.isEmpty) return;
    final last = messages.last;
    if (last.role != MessageRole.assistant) return;
    if (last.status == MessageStatus.streaming) return;
    if (last.id == _spokenMessageId) return;

    _awaitingReply = false;
    _spokenMessageId = last.id;
    _speakThenListen(last.displayText);
  }

  /// Speaks with a real voice when one is keyed, and with the platform engine
  /// otherwise.
  ///
  /// The platform engine is the reason voice mode was silent on iPhone:
  /// Safari's `speechSynthesis` is gated behind a user gesture that a reply
  /// arriving asynchronously does not have, and priming it only helps if the
  /// browser honours the priming. Playing returned audio has no such rule —
  /// it is the same path the voiceover cards already use, which do play.
  @visibleForTesting
  Future<bool> speakWithProvider(String spoken) async {
    final store = keys;
    final covered = managedProviders().contains('elevenlabs');
    if (store == null && !covered) return false;
    if (store != null && !store.hasKey('elevenlabs') && !covered) return false;

    // Membership first, then the member's own key — the same precedence the
    // turn pipeline uses, and for the same reason: they pay for the plan
    // monthly, so it is what should be spent, and running out of ceiling
    // degrades to their own key rather than dropping them back to the
    // platform's robot voice mid-sentence.
    final access = await managedAccess?.call('elevenlabs') ??
        (store == null ? null : DirectKey(store.keyFor('elevenlabs')));
    if (access == null) return false;

    try {
      final pcm = await _elevenLabs.speak(access: access, text: spoken);
      if (pcm.isEmpty) return false;
      final wav = AudioSynthService.wavFromPcm16(pcm,
          sampleRate: ElevenLabsClient.sampleRate);
      _player?.dispose();
      _playerEnded?.cancel();
      final player = WebAudioPlayer.fromWav(wav);
      _player = player;
      _playerEnded = player.onEnded.listen((_) {
        if (_running && phase == VoicePhase.speaking) _listen();
      });
      await player.play();
      return true;
    } catch (_) {
      return false; // fall through to the platform engine
    }
  }

  void _speakThenListen(String reply) {
    final spoken = speakableText(reply);
    if (spoken.isEmpty) {
      _listen();
      return;
    }
    _setPhase(VoicePhase.speaking);
    // A real voice first; the platform engine only if there is no voice key or
    // the call fails.
    speakWithProvider(spoken).then((spokenByProvider) {
      if (spokenByProvider || !_running) return;
      TtsService.speak(spoken);
    });
    // The TTS engines do not report completion uniformly across platforms, so
    // the pause is estimated from length rather than awaited. Reading too
    // early would talk over the answer; the estimate errs long.
    final seconds = (spoken.length / 14).clamp(2, 60).toDouble();
    Future<void>.delayed(Duration(milliseconds: (seconds * 1000).round()), () {
      if (_running && phase == VoicePhase.speaking) _listen();
    });
  }

  void _setPhase(VoicePhase next) {
    phase = next;
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

/// A reply reduced to what is worth saying out loud.
///
/// Pure, and separately tested, because this is where a voice conversation
/// most easily becomes absurd: read verbatim, a reply containing a code block
/// spells out every brace, and markdown emphasis is announced as "asterisk".
/// Fenced blocks are replaced by a short spoken note rather than dropped
/// silently — the answer did contain code, and not saying so is its own kind
/// of lie.
String speakableText(String markdown) {
  var text = markdown.replaceAll(
      RegExp(r'```[\s\S]*?```'), ' (the code is on screen) ');
  // An unterminated block — a reply cut off mid-code.
  text = text.replaceAll(RegExp(r'```[\s\S]*$'), ' (the code is on screen) ');
  text = text
      .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ')
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'^#{1,6}\s*', multiLine: true), '')
      .replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '')
      .replaceAll(RegExp(r'[*_`>]'), '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{2,}'), '\n')
      .trim();
  return text;
}
