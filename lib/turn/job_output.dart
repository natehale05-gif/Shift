import 'dart:typed_data';

/// What a step produced.
///
/// Sealed and typed on purpose. The alternative — passing untyped strings or
/// maps between steps — is how a video ends up spliced into an `<img>` tag: it
/// runs, it produces something, and the mistake is only visible to a person
/// looking at the result. Typed outputs let the graph refuse to be built.
sealed class JobOutput {
  const JobOutput();
}

/// Prose, code, or a structured payload a model wrote.
class TextOutput extends JobOutput {
  final String text;

  /// Set when the step asked for structured output and got valid JSON.
  /// Null when the step wanted prose, or when parsing failed — a caller that
  /// needs structure must check rather than assume, because "the model
  /// returned something" and "the model returned what was asked for" are
  /// different facts.
  final Object? json;

  const TextOutput(this.text, {this.json});
}

/// A still image.
class ImageOutput extends JobOutput {
  final Uint8List bytes;
  final String mimeType;

  /// What the image was asked to be, carried so a later step can caption it,
  /// alt-text it, or show it beside the request that produced it.
  final String prompt;

  const ImageOutput({
    required this.bytes,
    required this.mimeType,
    required this.prompt,
  });
}

/// Audio — speech or music. One type rather than two, because every consumer
/// treats them identically and a step that needs "some audio" should not have
/// to accept a union.
class AudioOutput extends JobOutput {
  final Uint8List bytes;
  final String mimeType;
  final Duration? duration;

  const AudioOutput({
    required this.bytes,
    required this.mimeType,
    this.duration,
  });
}

/// A video, which may still be rendering.
///
/// [bytes] is null while a provider is working — most video APIs submit and
/// then poll. A consumer that finds null must wait rather than treat it as
/// failure; a step that fails produces no output at all.
class VideoOutput extends JobOutput {
  final Uint8List? bytes;
  final String mimeType;
  final Uri? previewUrl;

  const VideoOutput({
    this.bytes,
    required this.mimeType,
    this.previewUrl,
  });
}

/// A real file with a real name — the thing a person downloads.
class FileOutput extends JobOutput {
  final Uint8List bytes;
  final String filename;
  final String mimeType;

  const FileOutput({
    required this.bytes,
    required this.filename,
    required this.mimeType,
  });
}

/// Sources found on the live web.
class SearchOutput extends JobOutput {
  final List<SearchResult> results;

  const SearchOutput(this.results);
}

class SearchResult {
  final String title;
  final Uri url;
  final String snippet;

  const SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });
}

/// The kinds of output a step can consume or produce, as a value.
///
/// Needed because the graph is validated *before* anything runs, when there
/// are no instances yet — only declarations of what each step will make.
enum OutputKind {
  text,
  image,
  audio,
  video,
  file,
  search;

  /// Whether [output] is an instance of this kind. Used to check a running
  /// graph against the shape it was validated as, which is not redundant with
  /// static validation: a provider can return the wrong thing.
  bool matches(JobOutput output) => switch (this) {
        OutputKind.text => output is TextOutput,
        OutputKind.image => output is ImageOutput,
        OutputKind.audio => output is AudioOutput,
        OutputKind.video => output is VideoOutput,
        OutputKind.file => output is FileOutput,
        OutputKind.search => output is SearchOutput,
      };
}
