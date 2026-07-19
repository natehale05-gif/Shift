import 'dart:math';

import '../models/studio_result.dart';
import '../models/studio_request.dart';
import '../models/studio_type.dart';

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
      'caption', 'script', 'hook', 'sales letter', 'ad copy', 'headline',
      'tagline', 'email copy', 'write me',
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
      "Here's my take: $trimmed\n\nI didn't spot a clear match for one of the five studios here, so I'm answering this one directly. Tell me if you'd rather I hand it off to Image, Video, Voice & Avatar, Music, or Copy & Scripts.",
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
      StudioType.middleware => '',
    };
  }

  static int seedFromString(String input) => input.codeUnits.fold<int>(
        7,
        (acc, c) => (acc * 31 + c) & 0x7fffffff,
      );

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
}
