import 'dart:typed_data';

/// Discriminated union of mock outputs a studio can attach to a chat message.
/// Every variant is fabricated client-side by [MockChatService] — there is no
/// real diffusion/video/voice/music model behind any of this.
sealed class StudioResult {
  const StudioResult();

  Map<String, dynamic> toJson();

  static StudioResult fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String) {
      'image' => ImageResult.fromJson(json),
      'video' => VideoResult.fromJson(json),
      'audio' => AudioResult.fromJson(json),
      'copy' => CopyResult.fromJson(json),
      'code' => CodeResult.fromJson(json),
      'translate' => TranslateResult.fromJson(json),
      'deck' => DeckResult.fromJson(json),
      'brandPack' => BrandPackResult.fromJson(json),
      'shortReels' => ShortReelsPackResult.fromJson(json),
      _ => throw ArgumentError('Unknown StudioResult type: ${json['type']}'),
    };
  }
}

class ImageResult extends StudioResult {
  final String prompt;
  final String aspectRatio;
  final String stylePreset;
  final int count;
  final int seed;

  const ImageResult({
    required this.prompt,
    required this.aspectRatio,
    required this.stylePreset,
    required this.count,
    required this.seed,
  });

  factory ImageResult.fromJson(Map<String, dynamic> json) => ImageResult(
        prompt: json['prompt'] as String,
        aspectRatio: json['aspectRatio'] as String,
        stylePreset: json['stylePreset'] as String,
        count: json['count'] as int,
        seed: json['seed'] as int,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'image',
        'prompt': prompt,
        'aspectRatio': aspectRatio,
        'stylePreset': stylePreset,
        'count': count,
        'seed': seed,
      };
}

class VideoResult extends StudioResult {
  final String prompt;
  final int durationSec;
  final String aspectRatio;
  final bool identityLock;
  final int seed;

  /// When this video was rendered by a real provider (Heygen), the URL of the
  /// finished clip. The app has no in-app player, so the card offers an "Open"
  /// link rather than embedding it. Null for simulated results.
  final String? videoUrl;

  /// Optional real thumbnail (provider CDN URL) used as the poster instead of
  /// the procedural gradient. Null for simulated results.
  final String? posterUrl;

  /// The provider label shown on the "Open in …" link (e.g. 'Heygen').
  final String? providerLabel;

  const VideoResult({
    required this.prompt,
    required this.durationSec,
    required this.aspectRatio,
    required this.identityLock,
    required this.seed,
    this.videoUrl,
    this.posterUrl,
    this.providerLabel,
  });

  bool get isRealVideo => videoUrl != null;

  factory VideoResult.fromJson(Map<String, dynamic> json) => VideoResult(
        prompt: json['prompt'] as String,
        durationSec: json['durationSec'] as int,
        aspectRatio: json['aspectRatio'] as String,
        identityLock: json['identityLock'] as bool,
        seed: json['seed'] as int,
        videoUrl: json['videoUrl'] as String?,
        posterUrl: json['posterUrl'] as String?,
        providerLabel: json['providerLabel'] as String?,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'video',
        'prompt': prompt,
        'durationSec': durationSec,
        'aspectRatio': aspectRatio,
        'identityLock': identityLock,
        'seed': seed,
        if (videoUrl != null) 'videoUrl': videoUrl,
        if (posterUrl != null) 'posterUrl': posterUrl,
        if (providerLabel != null) 'providerLabel': providerLabel,
      };
}

enum AudioKind { voice, music }

class AudioResult extends StudioResult {
  final AudioKind kind;
  final String title;
  final String subtitle;
  final int durationSec;
  final int seed;
  final String? transcript;

  const AudioResult({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.durationSec,
    required this.seed,
    this.transcript,
  });

  factory AudioResult.fromJson(Map<String, dynamic> json) => AudioResult(
        kind: AudioKind.values.firstWhere((e) => e.name == json['kind']),
        title: json['title'] as String,
        subtitle: json['subtitle'] as String,
        durationSec: json['durationSec'] as int,
        seed: json['seed'] as int,
        transcript: json['transcript'] as String?,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'audio',
        'kind': kind.name,
        'title': title,
        'subtitle': subtitle,
        'durationSec': durationSec,
        'seed': seed,
        'transcript': transcript,
      };
}

/// A document translation: the translated text plus its source and target
/// language. Downloadable as a .txt file. [live] is true when a real provider
/// produced it (vs a simulated demo).
class TranslateResult extends StudioResult {
  final String sourceText;
  final String targetLanguage;
  final String translatedText;
  final bool live;

  const TranslateResult({
    required this.sourceText,
    required this.targetLanguage,
    required this.translatedText,
    this.live = false,
  });

  factory TranslateResult.fromJson(Map<String, dynamic> json) =>
      TranslateResult(
        sourceText: json['sourceText'] as String,
        targetLanguage: json['targetLanguage'] as String,
        translatedText: json['translatedText'] as String,
        live: json['live'] as bool? ?? false,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'translate',
        'sourceText': sourceText,
        'targetLanguage': targetLanguage,
        'translatedText': translatedText,
        'live': live,
      };
}

/// One slide in a generated deck: a title and its bullet points.
class DeckSlide {
  final String title;
  final List<String> bullets;
  const DeckSlide({required this.title, this.bullets = const []});

  factory DeckSlide.fromJson(Map<String, dynamic> json) => DeckSlide(
        title: json['title'] as String? ?? '',
        bullets:
            (json['bullets'] as List<dynamic>? ?? const []).cast<String>(),
      );

  Map<String, dynamic> toJson() => {'title': title, 'bullets': bullets};
}

/// A generated slide deck. Downloadable as a real .pptx and previewable as an
/// HTML deck artifact. [live] is true when a provider wrote the outline.
class DeckResult extends StudioResult {
  final String title;
  final List<DeckSlide> slides;
  final bool live;

  const DeckResult({
    required this.title,
    required this.slides,
    this.live = false,
  });

  factory DeckResult.fromJson(Map<String, dynamic> json) => DeckResult(
        title: json['title'] as String,
        slides: (json['slides'] as List<dynamic>)
            .map((s) => DeckSlide.fromJson(s as Map<String, dynamic>))
            .toList(),
        live: json['live'] as bool? ?? false,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'deck',
        'title': title,
        'slides': slides.map((s) => s.toJson()).toList(),
        'live': live,
      };
}

/// A brand asset bundle: a logo, a colour palette, and a type pairing,
/// downloadable as a .zip kit. [logoPng] lives in memory for the session; on
/// reload it is regenerated procedurally from [seed] (real provider logos are
/// not persisted, matching attachments).
class BrandPackResult extends StudioResult {
  final String brandName;
  final List<String> palette; // '#RRGGBB'
  final String headingFont;
  final String bodyFont;
  final int seed;
  final bool live;
  final Uint8List? logoPng;

  const BrandPackResult({
    required this.brandName,
    required this.palette,
    required this.headingFont,
    required this.bodyFont,
    required this.seed,
    this.live = false,
    this.logoPng,
  });

  factory BrandPackResult.fromJson(Map<String, dynamic> json) =>
      BrandPackResult(
        brandName: json['brandName'] as String,
        palette: (json['palette'] as List<dynamic>).cast<String>(),
        headingFont: json['headingFont'] as String,
        bodyFont: json['bodyFont'] as String,
        seed: json['seed'] as int,
        live: json['live'] as bool? ?? false,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'brandPack',
        'brandName': brandName,
        'palette': palette,
        'headingFont': headingFont,
        'bodyFont': bodyFont,
        'seed': seed,
        'live': live,
        // logoPng intentionally omitted — regenerated from seed on reload.
      };
}

/// One short-form reel: a hook line, a shot-by-shot script, and a poster seed
/// (the poster is regenerated procedurally from the seed).
class ShortReel {
  final String hook;
  final String script;
  final int seed;
  const ShortReel({required this.hook, required this.script, required this.seed});

  factory ShortReel.fromJson(Map<String, dynamic> json) => ShortReel(
        hook: json['hook'] as String? ?? '',
        script: json['script'] as String? ?? '',
        seed: json['seed'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'hook': hook, 'script': script, 'seed': seed};
}

/// A short-form video pack: several reels, downloadable as a .zip (posters +
/// scripts + an HTML storyboard). [live] is true when a provider wrote the
/// scripts.
class ShortReelsPackResult extends StudioResult {
  final String topic;
  final List<ShortReel> reels;
  final bool live;

  const ShortReelsPackResult({
    required this.topic,
    required this.reels,
    this.live = false,
  });

  factory ShortReelsPackResult.fromJson(Map<String, dynamic> json) =>
      ShortReelsPackResult(
        topic: json['topic'] as String,
        reels: (json['reels'] as List<dynamic>)
            .map((r) => ShortReel.fromJson(r as Map<String, dynamic>))
            .toList(),
        live: json['live'] as bool? ?? false,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'shortReels',
        'topic': topic,
        'reels': reels.map((r) => r.toJson()).toList(),
        'live': live,
      };
}

class CopyResult extends StudioResult {
  final String contentType;
  final String tone;
  final String text;

  const CopyResult({
    required this.contentType,
    required this.tone,
    required this.text,
  });

  factory CopyResult.fromJson(Map<String, dynamic> json) => CopyResult(
        contentType: json['contentType'] as String,
        tone: json['tone'] as String,
        text: json['text'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'copy',
        'contentType': contentType,
        'tone': tone,
        'text': text,
      };
}

/// A generated code snippet, presented as a downloadable "artifact" (in the
/// same spirit as Claude's Artifacts panel) rather than an inline chat
/// bubble.
class CodeResult extends StudioResult {
  final String language;
  final String filename;
  final String code;

  const CodeResult({
    required this.language,
    required this.filename,
    required this.code,
  });

  factory CodeResult.fromJson(Map<String, dynamic> json) => CodeResult(
        language: json['language'] as String,
        filename: json['filename'] as String,
        code: json['code'] as String,
      );

  @override
  Map<String, dynamic> toJson() => {
        'type': 'code',
        'language': language,
        'filename': filename,
        'code': code,
      };
}
