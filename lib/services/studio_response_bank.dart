import 'dart:math';

import '../models/citation.dart';
import '../models/studio_result.dart';
import '../models/studio_request.dart';
import '../models/studio_type.dart';
import 'artifact_composition.dart';
import 'download_service.dart';

/// Canned templates and keyword tables backing [MockChatService]. Every
/// "generated" asset here is fabricated client-side — there is no real
/// diffusion/video/voice/music model behind this build.
class StudioResponseBank {
  StudioResponseBank._();

  static const Map<StudioType, List<String>> _keywords = {
    StudioType.imageStudio: [
      'image', 'photo', 'picture', 'logo', 'product shot', 'ad creative',
      'poster', 'graphic', 'illustration', 'thumbnail', 'banner',
    ],
    StudioType.videoStudio: [
      'video', 'clip', 'reel', 'shortreel', 'movie', 'trailer', 'ad video',
      'commercial', 'footage',
    ],
    StudioType.voiceAvatarStudio: [
      'voice', 'avatar', 'narrate', 'narration', 'clone my voice', 'dub',
      'talking head', 'voiceover',
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

  static String middlewareReply(String input) {
    final trimmed = input.trim();
    final templates = [
      "Here's my take: $trimmed\n\nI didn't spot a clear match for one of the six studios here, so I'm answering this one directly. Tell me if you'd rather I hand it off to Image, Video, Voice & Avatar, Music, Copy & Scripts, or Code.",
      "Got it — $trimmed\n\nThinking about this as your middleware AI: I can route this to a specialized studio if you want a generated asset, or keep chatting it through with you here. What would help most?",
      "On it. Taking \"$trimmed\" at face value, here's a quick pass — and if you want visuals, audio, video, or copy out of this, just say the word and I'll dispatch it to the right studio.",
    ];
    return templates[trimmed.length % templates.length];
  }

  static String routingIntro(StudioType studio, String input) {
    return switch (studio) {
      StudioType.imageStudio =>
        "Routing this to Image Studio — \"$input\" reads like a visual request.",
      StudioType.videoStudio =>
        "Routing this to Video Studio — sounds like you want a moving asset out of \"$input\".",
      StudioType.voiceAvatarStudio =>
        "Routing this to Voice & Avatar Studio for \"$input\".",
      StudioType.musicStudio =>
        "Routing this to Music Studio — let's score \"$input\".",
      StudioType.copyScriptsStudio =>
        "Routing this to Copy & Scripts Studio to write \"$input\".",
      StudioType.codeStudio =>
        "Routing this to Code Studio to build \"$input\".",
      StudioType.middleware => middlewareReply(input),
    };
  }

  static String studioFollowUp(StudioType studio) {
    return switch (studio) {
      StudioType.imageStudio => 'Here\'s a first pass — say the word to regenerate with a different style or ratio.',
      StudioType.videoStudio => 'Draft cut is ready below. I can extend the duration or lock identity further on request.',
      StudioType.voiceAvatarStudio => 'Voice pass is ready. I can switch voices, tone, or language on request.',
      StudioType.musicStudio => 'Track is scored and ready. Want a different mood or tempo?',
      StudioType.copyScriptsStudio => 'Copy is drafted below — tell me the tone or platform to tighten it.',
      StudioType.codeStudio => 'Here\'s a first pass below — downloadable as its own file. Tell me the language or a bug to fix and I\'ll revise it.',
      StudioType.middleware => '',
    };
  }

  static int _wordCount(String input) => input
      .trim()
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .length;

  /// A studio-specific clarifying question for prompts too thin to act on
  /// well — the same instinct a thoughtful collaborator (or Claude) has:
  /// ask before guessing. Returns null when the prompt already has enough
  /// to go on.
  static String? clarifyingQuestion(StudioType studio, String input) {
    final words = _wordCount(input);
    return switch (studio) {
      StudioType.imageStudio => words < 6
          ? "Happy to create that — a couple quick things first: what's "
              'the subject or brand, and any style or color preferences '
              '(minimal, playful, bold, a specific palette)?'
          : null,
      StudioType.videoStudio => words < 6
          ? "Happy to put that together — what's it for (an ad, a demo, "
              'a personal clip), and about how long should it run?'
          : null,
      StudioType.voiceAvatarStudio => words < 8
          ? 'I can do that — what should the voiceover actually say, and '
              'is there a tone or specific voice you have in mind?'
          : null,
      StudioType.musicStudio => words < 5
          ? 'Sure thing — what mood or genre are you thinking, and '
              'roughly how long should the track run?'
          : null,
      StudioType.copyScriptsStudio => words < 6
          ? "Happy to write that — what's it for (a caption, hook, "
              'script, ad copy, email), which platform, and what tone '
              'should it have?'
          : null,
      StudioType.codeStudio => words < 6
          ? 'Happy to build that — which language should I use, and can '
              'you say a bit more about what it should do?'
          : null,
      StudioType.middleware => null,
    };
  }

  /// Short acknowledgment used instead of the usual routing intro when
  /// this turn is answering a prior clarifying question rather than
  /// starting a fresh request.
  static String clarificationAck(StudioType studio) {
    return switch (studio) {
      StudioType.imageStudio => "Great, that's enough to go on.",
      StudioType.videoStudio => "Perfect, that's enough to go on.",
      StudioType.voiceAvatarStudio => 'Got it, generating that now.',
      StudioType.musicStudio => 'Got it, scoring that now.',
      StudioType.copyScriptsStudio => 'Got it, drafting that now.',
      StudioType.codeStudio => 'Got it, building that now.',
      StudioType.middleware => '',
    };
  }

  /// Intro for a request that spans two studios in one turn — e.g. "add a
  /// hero image / a video / background music to the website" — where one
  /// studio's output gets woven into an artifact another studio already built.
  static String compositionIntro(String artifactTitle,
      [ArtifactMediaKind kind = ArtifactMediaKind.image]) {
    final (studio, noun) = _composeWords(kind);
    return 'Routing this to $studio to generate the $noun, then adding it '
        'into your "$artifactTitle" artifact.';
  }

  static String compositionFollowUp(String artifactTitle,
      [ArtifactMediaKind kind = ArtifactMediaKind.image]) {
    final (_, noun) = _composeWords(kind);
    return 'Done — the new $noun is live in "$artifactTitle" as a new '
        'version. Ask for a different $noun or position anytime.';
  }

  static (String, String) _composeWords(ArtifactMediaKind kind) =>
      switch (kind) {
        ArtifactMediaKind.image => ('Image Studio', 'image'),
        ArtifactMediaKind.audio => ('Music Studio', 'soundtrack'),
        ArtifactMediaKind.video => ('Video Studio', 'video'),
      };

  /// Intro for a fresh page that several studios build together in one
  /// turn — e.g. "build me a dog treat website with several photos and a
  /// soundtrack" — naming the contributor studios pulled in.
  static String pageAssemblyIntro(String input, List<String> contributors) {
    final names = _joinNames(contributors);
    return 'Routing this to Code Studio to build "$input" — and pulling in '
        '$names to fill it in.';
  }

  static String pageAssemblyFollowUp(List<String> contributors) {
    final n = contributors.length;
    return 'Here\'s a first pass below, assembled with Code Studio and '
        '$n other ${n == 1 ? 'studio' : 'studios'} '
        '(${_joinNames(contributors)}) already in place. Ask for different '
        'visuals, copy, or audio anytime.';
  }

  static String _joinNames(List<String> names) {
    if (names.isEmpty) return 'the right studios';
    if (names.length == 1) return names.single;
    if (names.length == 2) return '${names[0]} and ${names[1]}';
    return '${names.sublist(0, names.length - 1).join(', ')}, and ${names.last}';
  }

  /// Deterministic landing-page copy (headline / body / CTA) for the mock's
  /// Copy & Scripts contributor. Structural record type so it's assignable to
  /// `PageCopy` without importing studio_composition (which would cycle).
  static ({String headline, String body, String cta}) pageCopy(String prompt) {
    final subject = prompt.trim().isEmpty ? 'Your brand' : prompt.trim();
    final seed = seedFromString(subject);
    const headlines = [
      'Made for the way you live.',
      'The upgrade you didn\'t know you needed.',
      'Simple, honest, and yours.',
      'Everything you love, nothing you don\'t.',
    ];
    const ctas = ['Get started', 'Shop now', 'Join today', 'Learn more'];
    return (
      headline: headlines[seed % headlines.length],
      body: '$subject — crafted with care and ready when you are. '
          'Thousands already made the shift; you\'re next.',
      cta: ctas[(seed ~/ 7) % ctas.length],
    );
  }

  // --- Copy & Scripts feeding another studio (mock script text) ----------

  /// A short spoken voiceover script the mock's Copy & Scripts contributor
  /// hands to Voice for narration.
  static String narrationScript(String prompt) {
    final subject = prompt.trim().isEmpty ? 'this' : prompt.trim();
    return 'Hi there, and welcome. We\'re so glad you\'re here. '
        'Everything you need for $subject is just a tap away — no fuss, no '
        'friction. This is SHIFT AI, and this is only the beginning.';
  }

  /// A short shot-by-shot video script (VO + on-screen) for the mock's
  /// Copy -> Video flow. Reuses the existing "Script" copy template.
  static String videoScriptText(String prompt) => _copyText(
        CopyScriptsRequest(
          contentType: 'Script',
          tone: 'Bold',
          platform: 'Web',
          brandNotes: prompt,
        ),
        seedFromString(prompt),
      );

  /// A jingle hook (title + two-line lyric) for the mock's Copy -> Music flow.
  static ({String title, String lyric}) jingleHook(String prompt) {
    final subject = prompt.trim().isEmpty ? 'your brand' : prompt.trim();
    return (
      title: _trackTitle('Uplifting', seedFromString(subject)),
      lyric: 'Feel the shift, hear it in the sound —\n'
          '$subject is turning it all around.',
    );
  }

  static int seedFromString(String input) => input.codeUnits.fold<int>(
        7,
        (acc, c) => (acc * 31 + c) & 0x7fffffff,
      );

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

  /// Short simulated reasoning, streamed into the collapsed thinking
  /// disclosure before the reply.
  static String thinkingText(StudioType studio, String input) {
    final subject = input.trim().isEmpty ? 'this request' : '"${input.trim()}"';
    return switch (studio) {
      StudioType.middleware =>
        'Reading $subject. No single studio clearly owns this, so I\'ll answer it directly as the middleware layer and offer routing options.',
      StudioType.codeStudio =>
        'Parsing $subject. This is a build request — Code Studio is the right executor. Sketching the file structure before generating.',
      _ =>
        'Parsing $subject. Intent maps to ${studio.displayName}, so I\'ll dispatch there and stream the result back inline.',
    };
  }

  static const _citationSources = [
    ['TechCrunch', 'techcrunch.com'],
    ['The Verge', 'theverge.com'],
    ['Reuters', 'reuters.com'],
    ['Ars Technica', 'arstechnica.com'],
    ['MIT Technology Review', 'technologyreview.com'],
  ];

  /// Deterministic canned citations for the simulated web-search pass.
  static List<Citation> cannedCitations(String input) {
    final seed = seedFromString(input);
    final slug = DownloadService.slugify(input, fallback: 'story');
    return List.generate(3, (i) {
      final source = _citationSources[(seed + i) % _citationSources.length];
      return Citation(
        title: '${source[0]}: ${input.trim()} — what we know',
        url: 'https://${source[1]}/2026/$slug-$i',
        citedText: 'Simulated source — add an API key for live web search.',
      );
    });
  }

  /// Reply text following a simulated web-search pass.
  static String searchSummary(String input) =>
      'Here\'s a quick simulated rundown on "${input.trim()}":\n\n'
      '- **What\'s known:** demo mode fabricates these findings locally; the '
      'sources below are placeholders.\n'
      '- **Why it matters:** once a real API key is added, this same flow '
      'runs a live web search and cites real pages.\n'
      '- **What to watch:** the citation chips under this message show how '
      'grounded answers will look.';

  /// A tiny self-contained landing page for HTML artifact demos.
  static String htmlArtifactContent(String prompt) {
    final title = prompt.trim().isEmpty ? 'Your Page' : prompt.trim();
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>$title</title>
<style>
  :root { color-scheme: light; }
  body { margin: 0; font-family: system-ui, sans-serif; background: #F5F4EF; color: #1d1d1f; }
  .hero { max-width: 640px; margin: 0 auto; padding: 96px 24px; text-align: center; }
  h1 { font-family: Georgia, serif; font-size: 44px; margin: 0 0 12px; }
  p { font-size: 18px; line-height: 1.6; color: #6e6e73; }
  .cta { display: inline-block; margin-top: 24px; padding: 12px 28px; border-radius: 999px;
         background: #AF52DE; color: #fff; text-decoration: none; font-weight: 600; }
</style>
</head>
<body>
  <main class="hero">
    <h1>$title</h1>
    <p>Generated by SHIFT AI's Code Studio. Edit this page by asking for changes in chat — each revision becomes a new version of this artifact.</p>
    <a class="cta" href="#">Get started</a>
  </main>
</body>
</html>
''';
  }

  static StudioResult buildResult(StudioRequest request) {
    final seed = seedFromString(request.summary);
    return switch (request) {
      ImageRequest r => ImageResult(
          prompt: r.prompt,
          aspectRatio: r.aspectRatio,
          stylePreset: r.stylePreset,
          count: r.count,
          seed: seed,
        ),
      VideoRequest r => VideoResult(
          prompt: r.prompt,
          durationSec: r.durationSec,
          aspectRatio: r.aspectRatio,
          identityLock: r.identityLock,
          seed: seed,
        ),
      VoiceAvatarRequest r => AudioResult(
          kind: AudioKind.voice,
          title: '${r.voice} · ${r.tone}',
          subtitle: 'for ${r.platform}',
          durationSec: max(4, (r.script.split(' ').length / 2.5).round()),
          seed: seed,
          transcript: r.script,
        ),
      MusicRequest r => AudioResult(
          kind: AudioKind.music,
          title: _trackTitle(r.mood, seed),
          subtitle: '${r.mood} · ${r.bpm} BPM',
          durationSec: r.durationSec,
          seed: seed,
        ),
      CopyScriptsRequest r => CopyResult(
          contentType: r.contentType,
          tone: r.tone,
          text: _copyText(r, seed),
        ),
      CodeRequest r => CodeResult(
          language: r.language,
          filename: _codeFilename(r.language, r.prompt),
          code: _codeSnippet(
            language: r.language,
            prompt: r.prompt,
            includeComments: r.includeComments,
          ),
        ),
    };
  }

  /// Fabricates a mock studio result from a free-form (keyword-routed)
  /// message, using sensible defaults since no structured form was filled.
  static StudioResult buildResultFromFreeform(StudioType studio, String input) {
    final seed = seedFromString(input);
    return switch (studio) {
      StudioType.imageStudio => ImageResult(
          prompt: input,
          aspectRatio: '1:1',
          stylePreset: 'Product Shot',
          count: 1,
          seed: seed,
        ),
      StudioType.videoStudio => VideoResult(
          prompt: input,
          durationSec: 10,
          aspectRatio: '16:9',
          identityLock: false,
          seed: seed,
        ),
      StudioType.voiceAvatarStudio => AudioResult(
          kind: AudioKind.voice,
          title: 'Aria · Friendly',
          subtitle: 'for Web',
          durationSec: max(4, (input.split(' ').length / 2.5).round()),
          seed: seed,
          transcript: input,
        ),
      StudioType.musicStudio => AudioResult(
          kind: AudioKind.music,
          title: _trackTitle('Uplifting', seed),
          subtitle: 'Uplifting · 100 BPM',
          durationSec: 30,
          seed: seed,
        ),
      StudioType.copyScriptsStudio => CopyResult(
          contentType: 'Caption',
          tone: 'Bold',
          text: _copyText(
            CopyScriptsRequest(
              contentType: 'Caption',
              tone: 'Bold',
              platform: 'Instagram',
              brandNotes: input,
            ),
            seed,
          ),
        ),
      StudioType.codeStudio => CodeResult(
          language: 'Python',
          filename: _codeFilename('Python', input),
          code: _codeSnippet(language: 'Python', prompt: input, includeComments: true),
        ),
      StudioType.middleware => throw ArgumentError('No studio result for middleware'),
    };
  }

  static const _moodAdjectives = {
    'Uplifting': ['Golden', 'Rising', 'Bright'],
    'Cinematic': ['Midnight', 'Horizon', 'Wide-Angle'],
    'Lo-fi': ['Hazy', 'Slow', 'Amber'],
    'Corporate': ['Clearline', 'Forward', 'Bluechip'],
  };
  static const _moodNouns = ['Horizon', 'Signal', 'Current', 'Skyline', 'Pulse'];

  static String _trackTitle(String mood, int seed) {
    final adjectives = _moodAdjectives[mood] ?? _moodAdjectives['Uplifting']!;
    final adjective = adjectives[seed % adjectives.length];
    final noun = _moodNouns[(seed ~/ 7) % _moodNouns.length];
    return '$adjective $noun';
  }

  static String _copyText(CopyScriptsRequest r, int seed) {
    final subject = r.brandNotes.isNotEmpty ? r.brandNotes : 'your brand';
    return switch (r.contentType) {
      'Hook' => '"You\'ve been doing $subject wrong — here\'s the 10-second fix."',
      'Caption' => '$subject, reimagined. Swipe to see why everyone\'s switching ->',
      'Script' =>
        '[OPEN on $subject]\nVO: "What if the hardest part of your day took ten seconds?"\n[CUT to product]\nVO: "That\'s $subject. That\'s the shift."',
      'Sales Letter' =>
        'Subject: The $subject shift starts today\n\nHi there,\n\nMost people wait until it\'s too late to change. You\'re not most people. Here\'s what $subject unlocks for you, starting now...',
      'Ad Copy' => 'Stop scrolling. $subject just changed the math. See it for yourself.',
      _ => '$subject — drafted in the ${r.tone} tone for ${r.platform}.',
    };
  }

  static const _codeExtensions = {
    'Python': 'py',
    'JavaScript': 'js',
    'TypeScript': 'ts',
    'Dart': 'dart',
    'Swift': 'swift',
    'SQL': 'sql',
    'HTML': 'html',
  };

  static String _codeFilename(String language, String prompt) =>
      '${_slug(prompt)}.${_codeExtensions[language] ?? 'txt'}';

  /// lower_snake_case identifier derived from the prompt, for use as a
  /// function name and base filename.
  static String _slug(String prompt) => DownloadService.slugify(prompt, fallback: 'snippet');

  /// lowerCamelCase identifier for languages that conventionally name
  /// functions that way.
  static String _camelSlug(String prompt) {
    final parts = _slug(prompt).split('_');
    if (parts.isEmpty) return 'snippet';
    return parts.first +
        parts.skip(1).map((w) => w.isEmpty ? '' : w[0].toUpperCase() + w.substring(1)).join();
  }

  static String _codeSnippet({
    required String language,
    required String prompt,
    required bool includeComments,
  }) {
    final snakeName = _slug(prompt);
    final camelName = _camelSlug(prompt);
    final doc = prompt.trim().isEmpty ? 'Generated snippet' : prompt.trim();

    final code = switch (language) {
      'Python' => '''
def $snakeName():
${includeComments ? '    """$doc"""\n' : ''}    # TODO: implement based on: $doc
    result = None
    return result


if __name__ == "__main__":
    print($snakeName())
''',
      'JavaScript' => '''
${includeComments ? '/**\n * $doc\n */\n' : ''}function $camelName() {
  // TODO: implement based on: $doc
  return null;
}

console.log($camelName());
''',
      'TypeScript' => '''
${includeComments ? '/**\n * $doc\n */\n' : ''}function $camelName(): unknown {
  // TODO: implement based on: $doc
  return null;
}

console.log($camelName());
''',
      'Dart' => '''
${includeComments ? '/// $doc\n' : ''}dynamic $camelName() {
  // TODO: implement based on: $doc
  return null;
}

void main() {
  print($camelName());
}
''',
      'Swift' => '''
${includeComments ? '/// $doc\n' : ''}func $camelName() -> Any? {
    // TODO: implement based on: $doc
    return nil
}

print($camelName())
''',
      'SQL' => '''
${includeComments ? '-- $doc\n' : ''}SELECT *
FROM your_table
WHERE 1 = 1; ${includeComments ? '-- TODO: refine based on: $doc' : ''}
''',
      'HTML' => '''
${includeComments ? '<!-- $doc -->\n' : ''}<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>${prompt.trim().isEmpty ? 'Untitled' : prompt.trim()}</title>
</head>
<body>
  ${includeComments ? '<!-- TODO: implement based on: $doc -->' : '<div></div>'}
</body>
</html>
''',
      _ => '// TODO: implement based on: $doc',
    };
    return code.trim();
  }
}
