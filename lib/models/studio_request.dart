import 'studio_type.dart';

/// A structured request submitted from one of the studio bottom-sheet forms,
/// bypassing keyword-based routing since the studio is already known.
sealed class StudioRequest {
  const StudioRequest();

  StudioType get studioType;

  /// A human-readable summary shown as the "user" chat bubble for this
  /// structured request.
  String get summary;
}

class ImageRequest extends StudioRequest {
  final String prompt;
  final String aspectRatio;
  final String stylePreset;
  final int count;

  const ImageRequest({
    required this.prompt,
    required this.aspectRatio,
    required this.stylePreset,
    required this.count,
  });

  @override
  StudioType get studioType => StudioType.imageStudio;

  @override
  String get summary =>
      '$prompt  ·  $stylePreset  ·  $aspectRatio  ·  ${count}x';
}

class VideoRequest extends StudioRequest {
  final String prompt;
  final int durationSec;
  final String aspectRatio;
  final bool identityLock;

  const VideoRequest({
    required this.prompt,
    required this.durationSec,
    required this.aspectRatio,
    required this.identityLock,
  });

  @override
  StudioType get studioType => StudioType.videoStudio;

  @override
  String get summary =>
      '$prompt  ·  ${durationSec}s  ·  $aspectRatio${identityLock ? '  ·  identity locked' : ''}';
}

class VoiceAvatarRequest extends StudioRequest {
  final String script;
  final String voice;
  final String tone;
  final String platform;

  const VoiceAvatarRequest({
    required this.script,
    required this.voice,
    required this.tone,
    required this.platform,
  });

  @override
  StudioType get studioType => StudioType.voiceAvatarStudio;

  @override
  String get summary => '$script  ·  $voice  ·  $tone  ·  for $platform';
}

class MusicRequest extends StudioRequest {
  final String mood;
  final int durationSec;
  final int bpm;

  const MusicRequest({
    required this.mood,
    required this.durationSec,
    required this.bpm,
  });

  @override
  StudioType get studioType => StudioType.musicStudio;

  @override
  String get summary => '$mood track  ·  ${durationSec}s  ·  $bpm BPM';
}

class CopyScriptsRequest extends StudioRequest {
  final String contentType;
  final String tone;
  final String platform;
  final String brandNotes;

  const CopyScriptsRequest({
    required this.contentType,
    required this.tone,
    required this.platform,
    required this.brandNotes,
  });

  @override
  StudioType get studioType => StudioType.copyScriptsStudio;

  @override
  String get summary =>
      '$contentType  ·  $tone  ·  for $platform${brandNotes.isNotEmpty ? '  ·  "$brandNotes"' : ''}';
}

class CodeRequest extends StudioRequest {
  final String prompt;
  final String language;
  final bool includeComments;

  const CodeRequest({
    required this.prompt,
    required this.language,
    required this.includeComments,
  });

  @override
  StudioType get studioType => StudioType.codeStudio;

  @override
  String get summary => '$prompt  ·  $language';
}
