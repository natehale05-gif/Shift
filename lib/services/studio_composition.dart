import '../models/artifact.dart';
import '../models/conversation.dart';
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

  /// For [CompositionKind.editArtifact]: the artifact the image is spliced
  /// into. Null for every other kind.
  final Artifact? editTarget;

  const CompositionPlan({
    required this.kind,
    required this.host,
    this.contributors = const {},
    this.editTarget,
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
  // 1. Splice an image into an artifact that already exists. Highest
  //    priority so "add a hero image to the website" never reads as a fresh
  //    multi-studio build.
  final editTarget = findArtifactCompositionTarget(conversation, input);
  if (editTarget != null) {
    return CompositionPlan(
      kind: CompositionKind.editArtifact,
      host: StudioType.imageStudio,
      contributors: const {StudioType.imageStudio},
      editTarget: editTarget,
    );
  }

  // 2. Code Studio builds a page and Image Studio fills it with photos in
  //    one turn (today's Code+Image behavior, now expressed as a plan).
  if (wantsCodeAndImageStudios(conversation, input)) {
    final contributors =
        detectStudios(input).intersection(_pageContributors);
    return CompositionPlan(
      kind: CompositionKind.pageAssembly,
      host: StudioType.codeStudio,
      contributors: contributors,
    );
  }

  return CompositionPlan.none;
}
