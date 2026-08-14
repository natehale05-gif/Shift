import '../turn/request_title.dart';

const _codeExtensions = {
  'dart': 'dart', 'python': 'py', 'py': 'py', 'javascript': 'js', 'js': 'js',
  'typescript': 'ts', 'ts': 'ts', 'json': 'json', 'yaml': 'yaml',
  'yml': 'yml', 'css': 'css', 'sql': 'sql', 'sh': 'sh', 'bash': 'sh',
  'java': 'java', 'kotlin': 'kt', 'swift': 'swift', 'go': 'go',
  'rust': 'rs', 'rs': 'rs', 'ruby': 'rb', 'rb': 'rb', 'c': 'c',
  'cpp': 'cpp', 'csharp': 'cs', 'php': 'php', 'xml': 'xml',
};

/// What kind of thing was made, which decides how it is shown.
enum ArtifactKind {
  html,
  svg,
  markdown,
  code;

  /// Unknown names read as [code] rather than throwing: an artifact stored by
  /// a later build should cost its preview, not the whole conversation.
  static ArtifactKind fromName(String name) => ArtifactKind.values.firstWhere(
        (e) => e.name == name,
        orElse: () => ArtifactKind.code,
      );
}

class ArtifactVersion {
  final String content;
  final DateTime createdAt;

  const ArtifactVersion({required this.content, required this.createdAt});

  Map<String, dynamic> toJson() => {
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  static ArtifactVersion? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final content = raw['content'];
    final created = DateTime.tryParse('${raw['createdAt']}');
    if (content is! String || created == null) return null;
    return ArtifactVersion(content: content, createdAt: created);
  }
}

/// A deliverable that lives beside the conversation rather than inside it — a
/// page, a document, a file — and gains a version each time it is revised.
///
/// Ported from v1, where the versions were what made "make the heading bigger"
/// a revision rather than a second page. Nothing here knows how it is drawn.
class Artifact {
  final String id;
  final String conversationId;
  final String title;
  final ArtifactKind kind;

  /// Highlighting language, for [ArtifactKind.code].
  final String? language;

  final List<ArtifactVersion> versions;

  const Artifact({
    required this.id,
    required this.conversationId,
    required this.title,
    required this.kind,
    this.language,
    required this.versions,
  });

  ArtifactVersion get latest => versions.last;

  /// Whether this is something a browser can render, as opposed to something
  /// only worth reading as source.
  bool get previewable =>
      kind == ArtifactKind.html || kind == ArtifactKind.svg;

  /// The name this downloads as.
  ///
  /// The extension comes from the kind rather than from the title, because the
  /// kind is what the bytes actually are — a page saved as `.txt` opens in a
  /// text editor and looks like the app produced nothing.
  String get filename =>
      '${fileStem(title, fallback: 'artifact')}.$extension';

  /// What the bytes are, as a file extension.
  String get extension => switch (kind) {
        ArtifactKind.html => 'html',
        ArtifactKind.svg => 'svg',
        ArtifactKind.markdown => 'md',
        // A code artifact's own language is the better answer when there is
        // one; `.txt` for a Python file would be the app forgetting what it
        // just wrote.
        ArtifactKind.code => _codeExtensions[language] ?? 'txt',
      };

  String get mimeType => switch (kind) {
        ArtifactKind.html => 'text/html',
        ArtifactKind.svg => 'image/svg+xml',
        ArtifactKind.markdown => 'text/markdown',
        ArtifactKind.code => 'text/plain',
      };

  Artifact withNewVersion(String content, DateTime createdAt) => Artifact(
        id: id,
        conversationId: conversationId,
        title: title,
        kind: kind,
        language: language,
        versions: [
          ...versions,
          ArtifactVersion(content: content, createdAt: createdAt),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'conversationId': conversationId,
        'title': title,
        'kind': kind.name,
        if (language != null) 'language': language,
        'versions': [for (final v in versions) v.toJson()],
      };

  /// Null rather than an exception when a stored artifact cannot be read, so
  /// one bad row costs itself and not the list around it.
  static Artifact? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final conversationId = raw['conversationId'];
    final title = raw['title'];
    if (id is! String || conversationId is! String || title is! String) {
      return null;
    }

    final versions = [
      for (final v in (raw['versions'] as List<dynamic>? ?? const []))
        ?ArtifactVersion.fromJson(v),
    ];
    // An artifact with no readable version has nothing to show, and showing an
    // empty panel is worse than not offering one.
    if (versions.isEmpty) return null;

    return Artifact(
      id: id,
      conversationId: conversationId,
      title: title,
      kind: ArtifactKind.fromName('${raw['kind']}'),
      language: raw['language'] as String?,
      versions: versions,
    );
  }
}
