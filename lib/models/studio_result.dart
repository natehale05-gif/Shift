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
