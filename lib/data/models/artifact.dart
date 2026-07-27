enum ArtifactKind {
  html,
  svg,
  markdown,
  code;

  static ArtifactKind fromName(String name) => ArtifactKind.values.firstWhere(
        (e) => e.name == name,
        orElse: () => ArtifactKind.code,
      );
}

class ArtifactVersion {
  final String content;
  final DateTime createdAt;

  const ArtifactVersion({required this.content, required this.createdAt});

  factory ArtifactVersion.fromJson(Map<String, dynamic> json) =>
      ArtifactVersion(
        content: json['content'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// A standalone piece of generated work (a web page, document, or code
/// file) that lives beside the conversation and accumulates versions as
/// the user iterates — the Claude-artifacts model.
class Artifact {
  final String id;
  final String conversationId;
  final String title;
  final ArtifactKind kind;

  /// Highlighting language for [ArtifactKind.code] artifacts.
  final String? language;

  /// True for self-contained interactive results (recipe cards, quizzes,
  /// flashcards, checklists). These render only — no code view — since the
  /// user asked for the thing, not its source. Website/app builds are false.
  final bool interactive;

  final List<ArtifactVersion> versions;

  const Artifact({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.kind,
    this.language,
    this.interactive = false,
    required this.versions,
  });

  ArtifactVersion get latest => versions.last;

  Artifact withNewVersion(String content, DateTime createdAt) => Artifact(
        id: id,
        conversationId: conversationId,
        title: title,
        kind: kind,
        language: language,
        interactive: interactive,
        versions: [
          ...versions,
          ArtifactVersion(content: content, createdAt: createdAt),
        ],
      );

  factory Artifact.fromJson(Map<String, dynamic> json) => Artifact(
        id: json['id'] as String,
        conversationId: json['conversationId'] as String,
        title: json['title'] as String,
        kind: ArtifactKind.fromName(json['kind'] as String),
        language: json['language'] as String?,
        interactive: json['interactive'] as bool? ?? false,
        versions: (json['versions'] as List<dynamic>)
            .map((e) => ArtifactVersion.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'title': title,
        'kind': kind.name,
        'language': language,
        if (interactive) 'interactive': true,
        'versions': versions.map((e) => e.toJson()).toList(),
      };
}
