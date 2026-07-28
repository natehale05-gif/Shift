import '../data/models/studio_type.dart';

/// Keyword routing: which studio a free-text request belongs to, and whether it
/// wants web search or a runnable HTML artifact.
///
/// Extracted from `studio_response_bank.dart`, which is otherwise 650 lines of
/// *simulated* reply copy. These three matchers are not simulation — they are
/// routing logic the **live** path depends on, and `turn/plan_turn.dart`,
/// `providers/router/model_router.dart` and `services/studio_composition.dart`
/// all import them. Keeping them here means the live router no longer pulls in
/// the demo response bank just to match keywords, and the bank now means
/// exactly one thing: what demo mode says.
class StudioDetection {

  static const Map<StudioType, List<String>> _keywords = {
    // The new deliverable/specific studios are checked first so they win over
    // the broader Image/Video/Music keywords.
    StudioType.translateStudio: [
      'translate', 'translation', 'translated', 'localize', 'localise',
      'localization', 'localisation',
    ],
    StudioType.deckStudio: [
      'slide deck', 'slides', 'powerpoint', 'power point', 'pptx', 'keynote',
      'pitch deck', 'presentation', 'deck',
    ],
    StudioType.brandPackStudio: [
      'brand pack', 'brand kit', 'brand bundle', 'brand assets',
      'brand identity', 'brand guidelines', 'logo pack', 'style guide',
      'brand book',
    ],
    StudioType.shortReelsStudio: [
      'shortreels', 'short reels', 'reels pack', 'short-form', 'short form',
      'shorts', 'tiktok', 'tiktoks', 'batch of reels', 'reels for',
    ],
    StudioType.avatarStudio: [
      'avatar', 'talking head', 'talking-head', 'spokesperson',
      'presenter video', 'digital human',
    ],
    StudioType.voiceStudio: [
      'voiceover', 'voice over', 'voice-over', 'narrate', 'narration',
      'read aloud', 'text to speech', 'text-to-speech', 'tts',
      'clone my voice', 'dub', 'voice',
    ],
    StudioType.imageStudio: [
      'image', 'photo', 'picture', 'logo', 'product shot', 'ad creative',
      'poster', 'graphic', 'illustration', 'thumbnail', 'banner',
    ],
    StudioType.videoStudio: [
      'video', 'clip', 'reel', 'movie', 'trailer', 'ad video',
      'commercial', 'footage',
    ],
    StudioType.musicStudio: [
      'music', 'song', 'beat', 'soundtrack', 'jingle', 'track', 'audio bed',
    ],
    StudioType.copyScriptsStudio: [
      // Note: a compound phrase containing "video" (e.g. "video script")
      // would still match videoStudio's bare "video" keyword first, since
      // that studio is checked earlier below — reasonable, since wanting a
      // video script often does mean wanting the video itself.
      'caption', 'hook', 'sales letter', 'ad copy', 'headline', 'tagline',
      'email copy', 'ad script', 'sales script',
    ],
    StudioType.codeStudio: [
      'code', 'function', 'algorithm', 'debug', 'refactor', 'programming',
      'python', 'javascript', 'typescript', 'dart', 'swift', 'sql query',
      'regex', 'bug fix', 'unit test', 'api endpoint', 'shell script',
      'script', // bare "script" reads as a programming script in this app
      // Page-building requests are code requests (they produce runnable
      // HTML artifacts).
      'landing page', 'website', 'web page', 'webpage', 'html', 'homepage',
    ],
  };


  /// Keyword/regex intent detection over free-form chat text. Returns
  /// [StudioType.middleware] when nothing matches — the middleware AI
  /// answers directly rather than routing anywhere.
  static StudioType detectStudio(String input) {
    final lower = input.toLowerCase();
    for (final entry in _keywords.entries) {
      for (final keyword in entry.value) {
        if (lower.contains(keyword)) return entry.key;
      }
    }
    return StudioType.middleware;
  }

  static const _searchKeywords = [
    'search', 'news', 'latest', 'today', 'this week', 'current',
    'what happened', 'who won', 'look up', 'find out', 'research',
  ];

  /// Whether the prompt reads like it wants fresh information from the web
  /// (drives the mock's simulated web-search tool pass).
  static bool wantsWebSearch(String input) {
    final lower = input.toLowerCase();
    return _searchKeywords.any(lower.contains);
  }

  static const _htmlArtifactKeywords = [
    'landing page', 'website', 'web page', 'webpage', 'html page',
    'portfolio page', 'homepage',
  ];

  /// Whether a code-routed prompt should produce a runnable HTML artifact
  /// rather than a plain code file.
  static bool wantsHtmlArtifact(String input) {
    final lower = input.toLowerCase();
    return _htmlArtifactKeywords.any(lower.contains);
  }
}
