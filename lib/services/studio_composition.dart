import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../models/artifact.dart';
import '../models/conversation.dart';
import '../models/studio_result.dart';
import '../models/studio_type.dart';
import 'artifact_composition.dart';
import 'studio_response_bank.dart';

/// How a single prompt asks two or more studios to work together. The
/// middleware picks exactly one plan per turn; [CompositionKind.none] is the
/// ordinary single-studio path (the router decides the studio).
enum CompositionKind {
  /// One studio. The router/keyword path picks it, as before.
  none,

  /// An image spliced into an HTML artifact that already exists
  /// ("add a hero image to the website").
  editArtifact,

  /// Code Studio builds a page and other studios fill it in the same turn
  /// (photos, real copy, an audio player, a video block).
  pageAssembly,

  /// Copy & Scripts writes a script, then Voice narrates it.
  narratedScript,

  /// Copy & Scripts writes a script, then Video produces a clip from it.
  scriptedVideo,

  /// Copy & Scripts writes a hook/lyric, then Music scores a track for it.
  jingle,

  /// Image generates a portrait shown together with a Voice narration.
  talkingAvatar,

  /// Voice narration presented over a Music bed (a single simulated mix).
  scoredNarration,
}

/// The middleware's composition decision for one turn: which studios are
/// involved and how their outputs combine.
class CompositionPlan {
  final CompositionKind kind;

  /// The studio whose card or artifact is the container for the result.
  final StudioType host;

  /// Studios feeding the host (may include the host itself).
  final Set<StudioType> contributors;

  /// For [CompositionKind.editArtifact]: the artifact the media is spliced
  /// into. Null for every other kind.
  final Artifact? editTarget;

  /// For [CompositionKind.editArtifact]: which kind of media block to embed
  /// (image, audio, or video). Null for every other kind.
  final ArtifactMediaKind? editKind;

  const CompositionPlan({
    required this.kind,
    required this.host,
    this.contributors = const {},
    this.editTarget,
    this.editKind,
  });

  static const none = CompositionPlan(
    kind: CompositionKind.none,
    host: StudioType.middleware,
  );
}

// Per-contributor trigger phrases, tuned for *explicit* multi-studio
// requests. These are intentionally separate from
// `StudioResponseBank.detectStudio`'s single-studio keyword tables: a combo
// only fires when the user clearly names the contributor, so a plain
// "build me a landing page" stays code-only.
const _imageTriggers = [
  'image', 'images', 'photo', 'photos', 'picture', 'pictures', 'logo',
  'graphic', 'graphics', 'illustration', 'illustrations', 'banner',
  'thumbnail', 'icon', 'gallery', 'headshot', 'portrait',
];

const _copyTriggers = [
  'copy', 'copywriting', 'headline', 'headlines', 'tagline', 'slogan',
  'caption', 'captions', 'hook', 'wording', 'blurb', 'ad copy',
  'sales letter', 'email copy', 'body text',
];

const _musicTriggers = [
  'music', 'soundtrack', 'song', 'background music', 'jingle', 'score',
  'audio bed', 'backing track', 'theme song',
];

const _voiceTriggers = [
  'voiceover', 'voice-over', 'voice over', 'narration', 'narrate',
  'narrated', 'voiceovers', 'audio guide', 'read aloud', 'spoken',
  'voice',
];

const _videoTriggers = [
  'video', 'videos', 'clip', 'reel', 'footage', 'animation',
];

bool _mentions(String lower, List<String> triggers) =>
    triggers.any(lower.contains);

/// Every studio a prompt *explicitly* names (multi-label), used to decide
/// which studios collaborate on a turn. Unlike
/// `StudioResponseBank.detectStudio` (first-match, single studio), this
/// returns the full set.
Set<StudioType> detectStudios(String input) {
  final lower = input.toLowerCase();
  return {
    if (StudioResponseBank.wantsHtmlArtifact(input)) StudioType.codeStudio,
    if (_mentions(lower, _imageTriggers)) StudioType.imageStudio,
    if (_mentions(lower, _copyTriggers)) StudioType.copyScriptsStudio,
    if (_mentions(lower, _musicTriggers)) StudioType.musicStudio,
    if (_mentions(lower, _voiceTriggers)) StudioType.voiceAvatarStudio,
    if (_mentions(lower, _videoTriggers)) StudioType.videoStudio,
  };
}

const _pageContributors = {
  StudioType.imageStudio,
  StudioType.copyScriptsStudio,
  StudioType.musicStudio,
  StudioType.voiceAvatarStudio,
  StudioType.videoStudio,
};

/// The single composition decision for a turn. First match wins, so the
/// kinds are mutually exclusive by priority. Only the framework-wired kinds
/// ([none], [editArtifact], [pageAssembly]) are returned today; the
/// remaining kinds are added as their handlers ship.
CompositionPlan planComposition(Conversation conversation, String input) {
  // 1. Splice a generated asset (image, audio, or video) into an artifact
  //    that already exists. Highest priority so "add a hero image / a video /
  //    background music to the website" never reads as a fresh multi-studio
  //    build.
  final edit = findArtifactEdit(conversation, input);
  if (edit != null) {
    final host = switch (edit.kind) {
      ArtifactMediaKind.image => StudioType.imageStudio,
      ArtifactMediaKind.audio => StudioType.musicStudio,
      ArtifactMediaKind.video => StudioType.videoStudio,
    };
    return CompositionPlan(
      kind: CompositionKind.editArtifact,
      host: host,
      contributors: {host},
      editTarget: edit.target,
      editKind: edit.kind,
    );
  }

  // 2. Code Studio builds a page and other studios fill it in one turn:
  //    photos, real copy, an audio player, a video block. Fires only on a
  //    fresh page request that also names at least one contributor — a plain
  //    "build me a landing page" stays code-only. Mutually exclusive with the
  //    edit path above (no existing artifact, no "…to the website" wording).
  final studios = detectStudios(input);
  if (studios.contains(StudioType.codeStudio) &&
      latestHtmlArtifact(conversation) == null &&
      !referencesExistingArtifact(input)) {
    final contributors = studios.intersection(_pageContributors);
    if (contributors.isNotEmpty) {
      return CompositionPlan(
        kind: CompositionKind.pageAssembly,
        host: StudioType.codeStudio,
        contributors: contributors,
      );
    }
  }

  // 3. Copy & Scripts writes something, then another studio produces from
  //    it — "write and narrate…", "write a video script and make it",
  //    "write a jingle". Requires an explicit write/script signal plus the
  //    downstream media studio (and not a page request, handled above).
  if (_wantsWritten(input)) {
    if (studios.contains(StudioType.voiceAvatarStudio)) {
      return _copyFedPlan(CompositionKind.narratedScript);
    }
    if (studios.contains(StudioType.videoStudio)) {
      return _copyFedPlan(CompositionKind.scriptedVideo);
    }
    if (studios.contains(StudioType.musicStudio)) {
      return _copyFedPlan(CompositionKind.jingle);
    }
  }

  // 4. Media pairs. Talking avatar = an Image portrait shown with a Voice
  //    narration; scored narration = Voice over a Music bed.
  final hasImage = studios.contains(StudioType.imageStudio);
  final hasVoice = studios.contains(StudioType.voiceAvatarStudio);
  final hasMusic = studios.contains(StudioType.musicStudio);
  if (_wantsAvatar(input) || (hasImage && hasVoice)) {
    return const CompositionPlan(
      kind: CompositionKind.talkingAvatar,
      host: StudioType.avatarStudio,
      contributors: {StudioType.imageStudio, StudioType.voiceStudio},
    );
  }
  if (hasVoice && hasMusic) {
    return const CompositionPlan(
      kind: CompositionKind.scoredNarration,
      host: StudioType.voiceStudio,
      contributors: {StudioType.voiceStudio, StudioType.musicStudio},
    );
  }

  return CompositionPlan.none;
}

final _avatarSignal = RegExp(
    r'\b(avatar|talking head|talking avatar|spokesperson|virtual presenter)\b');

bool _wantsAvatar(String input) => _avatarSignal.hasMatch(input.toLowerCase());

final _writtenSignal = RegExp(
    r'\b(write|writes|writing|written|draft|drafts|script|scripts|scripted|'
    r'compose|lyrics?)\b');

bool _wantsWritten(String input) => _writtenSignal.hasMatch(input.toLowerCase());

CompositionPlan _copyFedPlan(CompositionKind kind) => CompositionPlan(
      kind: kind,
      host: copyFedHost(kind),
      contributors: {StudioType.copyScriptsStudio, copyFedHost(kind)},
    );

/// True for the three Copy-feeds-media kinds.
bool isCopyFed(CompositionKind kind) =>
    kind == CompositionKind.narratedScript ||
    kind == CompositionKind.scriptedVideo ||
    kind == CompositionKind.jingle;

/// The studio whose result card carries a copy-fed turn's output.
StudioType copyFedHost(CompositionKind kind) => switch (kind) {
      CompositionKind.narratedScript => StudioType.voiceAvatarStudio,
      CompositionKind.scriptedVideo => StudioType.videoStudio,
      CompositionKind.jingle => StudioType.musicStudio,
      _ => StudioType.middleware,
    };

String copyFedIntro(CompositionKind kind) => switch (kind) {
      CompositionKind.narratedScript => 'Writing the script and voicing it…',
      CompositionKind.scriptedVideo => 'Writing the script and filming it…',
      CompositionKind.jingle => 'Writing the hook and scoring it…',
      _ => '',
    };

String copyFedFollowUp(CompositionKind kind) => switch (kind) {
      CompositionKind.narratedScript =>
        'Script written and voiced above. Want a different tone or voice?',
      CompositionKind.scriptedVideo =>
        'Script written and the clip is drafted above. I can adjust the '
            'scenes or length.',
      CompositionKind.jingle =>
        'Hook written and scored above. Want a different mood or tempo?',
      _ => '',
    };

/// The instruction handed to a live text model (Claude/Gemini) to write the
/// script for a copy-fed or media-pair turn.
String scriptLlmPrompt(CompositionKind kind, String userInput) => switch (kind) {
      CompositionKind.narratedScript ||
      CompositionKind.talkingAvatar ||
      CompositionKind.scoredNarration =>
        'Write a short, warm spoken voiceover script (3-4 sentences) for: '
            '"$userInput". Output only the words to be spoken — no stage '
            'directions, no quotes.',
      CompositionKind.scriptedVideo =>
        'Write a short video script with 3-4 shots (each a brief on-screen '
            'note plus a VO line) for: "$userInput". Keep it under 120 words.',
      CompositionKind.jingle =>
        'Write a catchy two-line jingle hook (lyrics only) for: "$userInput".',
      _ => userInput,
    };

/// The mock's template script when no live text model wrote one.
String mockScript(CompositionKind kind, String userInput) => switch (kind) {
      CompositionKind.narratedScript ||
      CompositionKind.talkingAvatar ||
      CompositionKind.scoredNarration =>
        StudioResponseBank.narrationScript(userInput),
      CompositionKind.scriptedVideo =>
        StudioResponseBank.videoScriptText(userInput),
      CompositionKind.jingle => StudioResponseBank.jingleHook(userInput).lyric,
      _ => '',
    };

// --- Media pairs -----------------------------------------------------------

bool isMediaPair(CompositionKind kind) =>
    kind == CompositionKind.talkingAvatar ||
    kind == CompositionKind.scoredNarration;

/// Talking-avatar leads with the Avatar studio; scored narration leads with
/// Voice (the narration is the throughline).
StudioType mediaPairHost(CompositionKind kind) => switch (kind) {
      CompositionKind.talkingAvatar => StudioType.avatarStudio,
      _ => StudioType.voiceStudio,
    };

String mediaPairIntro(CompositionKind kind) => switch (kind) {
      CompositionKind.talkingAvatar =>
        'Making the portrait and giving it a voice…',
      CompositionKind.scoredNarration =>
        'Recording the narration over a music bed…',
      _ => '',
    };

String mediaPairFollowUp(CompositionKind kind) => switch (kind) {
      CompositionKind.talkingAvatar =>
        'Portrait and voiceover are ready above. Want a different look or '
            'voice?',
      CompositionKind.scoredNarration =>
        'Narration and music bed are ready above. Want a different mood or '
            'tempo?',
      _ => '',
    };

/// The audio card a media-pair turn attaches. talkingAvatar plays a
/// speech-like voice; scoredNarration plays a music bed with the narration
/// shown as the transcript (the synth renders one track, so the "mix" is
/// represented as the bed plus the written narration).
AudioResult mediaPairAudio(
    CompositionKind kind, String userInput, String script) {
  final seed = StudioResponseBank.seedFromString(userInput);
  return switch (kind) {
    CompositionKind.talkingAvatar => AudioResult(
        kind: AudioKind.voice,
        title: 'Avatar voice',
        subtitle: 'Voiceover',
        durationSec: max(4, (script.split(' ').length / 2.5).round()),
        seed: seed,
        transcript: script,
      ),
    CompositionKind.scoredNarration => AudioResult(
        kind: AudioKind.music,
        title: 'Narration over a music bed',
        subtitle: 'Music bed · voiceover',
        durationSec: 20,
        seed: seed,
        transcript: script,
      ),
    _ => throw ArgumentError('not a media pair: $kind'),
  };
}

/// The media result a copy-fed turn attaches, carrying the written [script].
StudioResult copyFedResult(
    CompositionKind kind, String userInput, String script) {
  final seed = StudioResponseBank.seedFromString(userInput);
  return switch (kind) {
    CompositionKind.narratedScript => AudioResult(
        kind: AudioKind.voice,
        title: 'Narration',
        subtitle: 'Voiceover',
        durationSec: max(4, (script.split(' ').length / 2.5).round()),
        seed: seed,
        transcript: script,
      ),
    CompositionKind.scriptedVideo => VideoResult(
        prompt: script,
        durationSec: 15,
        aspectRatio: '16:9',
        identityLock: false,
        seed: seed,
      ),
    CompositionKind.jingle => AudioResult(
        kind: AudioKind.music,
        title: StudioResponseBank.jingleHook(userInput).title,
        subtitle: 'Uplifting · 100 BPM',
        durationSec: 20,
        seed: seed,
        transcript: script,
      ),
    _ => throw ArgumentError('not a copy-fed kind: $kind'),
  };
}

// ---------------------------------------------------------------------------
// Page assembly — pure HTML string surgery that weaves each contributor
// studio's output into the Code Studio artifact. All keyed off the <body>
// tag, like the existing embedImage* helpers, so they behave identically for
// mock-generated and live-generated bytes.
// ---------------------------------------------------------------------------

/// Real copy from Copy & Scripts to drop into a page's hero.
typedef PageCopy = ({String headline, String body, String cta});

String _esc(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _insertAfterBody(String html, String fragment) {
  final m = RegExp(r'<body[^>]*>', caseSensitive: false).firstMatch(html);
  if (m == null) return '$fragment\n$html';
  return '${html.substring(0, m.end)}\n$fragment${html.substring(m.end)}';
}

/// Replaces the mock hero template's `<h1>`/`<p>`/`.cta` text with real copy.
/// Best-effort: any piece the template doesn't contain is skipped, so it's a
/// no-op on HTML that has no hero (e.g. a page a live model wrote itself, which
/// already carries its own copy).
String embedCopyIntoPage(
  String html, {
  String? headline,
  String? body,
  String? cta,
}) {
  var out = html;
  if (headline != null) {
    out = out.replaceFirst(
        RegExp(r'<h1>.*?</h1>', dotAll: true), '<h1>${_esc(headline)}</h1>');
  }
  if (body != null) {
    out = out.replaceFirst(
        RegExp(r'<p>.*?</p>', dotAll: true), '<p>${_esc(body)}</p>');
  }
  if (cta != null) {
    out = out.replaceFirstMapped(
      RegExp(r'(<a class="cta"[^>]*>).*?(</a>)', dotAll: true),
      (m) => '${m[1]}${_esc(cta)}${m[2]}',
    );
  }
  return out;
}

/// Inserts a playable `<audio>` player (WAV as a base64 data URI) after the
/// opening `<body>` — the page's embedded soundtrack or voiceover.
String embedAudioPlayer(
  String html,
  Uint8List wavBytes, {
  String label = 'Audio',
}) {
  final uri = 'data:audio/wav;base64,${base64Encode(wavBytes)}';
  final figure = '<figure style="max-width:640px;margin:0 auto 24px;'
      'padding:0 24px;text-align:center;">'
      '<figcaption style="font:600 14px system-ui;color:#6e6e73;'
      'margin-bottom:8px;">${_esc(label)}</figcaption>'
      '<audio controls src="$uri" style="width:100%;"></audio></figure>';
  return _insertAfterBody(html, figure);
}

/// Inserts a video figure — a poster image with a play badge and a
/// "Simulated video" caption (there is no real video model behind this).
String embedVideoBlock(
  String html,
  Uint8List posterPng, {
  String label = 'Video',
}) {
  final uri = 'data:image/png;base64,${base64Encode(posterPng)}';
  final figure = '<figure style="max-width:640px;margin:0 auto 24px;'
      'padding:0 24px;position:relative;">'
      '<img src="$uri" alt="${_esc(label)}" '
      'style="width:100%;border-radius:12px;display:block;" />'
      '<div style="position:absolute;inset:0 24px;display:flex;'
      'align-items:center;justify-content:center;pointer-events:none;">'
      '<div style="width:64px;height:64px;border-radius:50%;'
      'background:rgba(0,0,0,0.55);color:#fff;display:flex;'
      'align-items:center;justify-content:center;font-size:26px;">&#9654;</div>'
      '</div>'
      '<figcaption style="font:600 13px system-ui;color:#6e6e73;'
      'margin-top:8px;">Simulated video · ${_esc(label)}</figcaption></figure>';
  return _insertAfterBody(html, figure);
}

/// Weaves any subset of contributor outputs into a page in one pass. Media
/// blocks are inserted so they read top-to-bottom as gallery → audio → video
/// (each `embed*` call inserts right after `<body>`, so they're applied in
/// reverse display order). Copy is replaced in place in the hero.
String assemblePage(
  String baseHtml, {
  List<Uint8List> images = const [],
  PageCopy? copy,
  Uint8List? audioWav,
  String audioLabel = 'Soundtrack',
  Uint8List? videoPoster,
  String videoLabel = 'Clip',
  String altText = 'Generated image',
}) {
  var html = baseHtml;
  if (copy != null) {
    html = embedCopyIntoPage(html,
        headline: copy.headline, body: copy.body, cta: copy.cta);
  }
  if (videoPoster != null) {
    html = embedVideoBlock(html, videoPoster, label: videoLabel);
  }
  if (audioWav != null) html = embedAudioPlayer(html, audioWav, label: audioLabel);
  if (images.isNotEmpty) html = embedImageGallery(html, images, altText: altText);
  return html;
}
