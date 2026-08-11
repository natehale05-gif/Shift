/// A note, as the list needs it.
///
/// Separate from the body for the same reason conversations are: the list is
/// drawn the moment the mode opens, and reading every note's text to draw a
/// list of titles is work a phone does not need to do.
class NoteSummary {
  final String id;
  final String title;
  final DateTime updatedAt;

  /// The first line or so, for the second row. Held in the index rather than
  /// read from the body, because it is exactly what the list wants and nothing
  /// else about the body is.
  final String preview;

  const NoteSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
    this.preview = '',
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        if (preview.isNotEmpty) 'preview': preview,
      };

  static NoteSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    final updated = DateTime.tryParse('${raw['updatedAt']}');
    if (id is! String || title is! String || updated == null) return null;
    return NoteSummary(
      id: id,
      title: title,
      updatedAt: updated,
      preview: raw['preview'] as String? ?? '',
    );
  }
}

/// What a note is called, derived from what is in it.
///
/// Notes are dictated, so nobody types a title first — and a list of notes all
/// called "Untitled" is a list you cannot use. The first line is the title if
/// it reads like one; otherwise the opening words are, trimmed at a word
/// boundary.
///
/// Pure, and deliberately not the same rule as [titleFromRequest]: that one
/// strips a *request* preamble ("build me a…"), which is wrong here. Someone
/// who says "make sure I call the dentist" has written a note whose subject is
/// the whole sentence.
String noteTitleFrom(String body, {String fallback = 'New note'}) {
  final text = body.trim();
  if (text.isEmpty) return fallback;

  final firstLine = text.split('\n').first.trim();
  // A markdown heading is a title someone wrote on purpose.
  final heading = RegExp(r'^#{1,6}\s+(.*)$').firstMatch(firstLine);
  final candidate = heading != null ? heading.group(1)!.trim() : firstLine;
  if (candidate.isEmpty) return fallback;

  const limit = 60;
  if (candidate.length <= limit) return candidate;

  final cut = candidate.substring(0, limit);
  final lastSpace = cut.lastIndexOf(' ');
  // Cutting mid-word reads as a bug; cutting at a space reads as a title.
  return '${lastSpace > 20 ? cut.substring(0, lastSpace) : cut}…';
}

/// The second line of a row: what the note says, once its title is out of the
/// way. Empty when the note is only its title, so the row does not carry a
/// blank line pretending to be content.
String notePreviewFrom(String body) {
  final lines = body.trim().split('\n');
  final rest = lines.skip(1).join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (rest.isEmpty) return '';
  return rest.length <= 120 ? rest : '${rest.substring(0, 120)}…';
}
