/// Turns a finished reply into a deliverable, or decides it has none.
///
/// Pure, so the decision can be pinned against recorded replies with no
/// provider, no widgets and no clock beyond the one passed in.
///
/// **The interesting half is when *not* to.** A reply is a deliverable when the
/// person asked for a file and got one; it is not when they asked a question
/// and the answer happens to quote some code. Getting that backwards in either
/// direction is a real cost: pull a six-line CSS snippet into a side panel and
/// the answer to "how do I centre a div" has been hidden behind a tab; leave a
/// whole web page in the transcript and the app's centrepiece output arrives as
/// an unreadable wall of markup.
library;

import '../data/artifact.dart';
import 'request_title.dart';

final _fencedBlock = RegExp(r'```([A-Za-z0-9+#_-]*)\n([\s\S]*?)```');

/// Blocks shorter than this are an illustration, not a file. Carried from v1,
/// where it shipped.
const _minimumLines = 5;

/// How much of the reply the block has to be before it counts as *the answer*
/// rather than part of one.
///
/// This replaces v1's gate, which asked what the router had decided the turn
/// was for. v2 has no route — every text step runs the same path — so the
/// question is answered from the reply itself, which is better evidence
/// anyway: a classifier reading only the request guessed wrong often enough
/// that v1 needed a second rule (F4) to catch what it missed.
const _majority = 0.6;

/// Whether [code] is a complete HTML document.
///
/// Deliberately narrow — a doctype, or `<html>` paired with `</html>`. A
/// handful of tags quoted to explain something is not a page, and matching any
/// HTML at all would turn every answer mentioning a `<div>` into an artifact.
bool isWholeDocument(String code) {
  final lower = code.trim().toLowerCase();
  return lower.startsWith('<!doctype html') ||
      (lower.contains('<html') && lower.contains('</html>'));
}

/// The artifact [reply] produced, or null if it produced none.
///
/// [request] names it only as a fallback: a finished page carries a better name
/// than the errand that asked for it, which is what [titleFromArtifact] is for.
Artifact? extractArtifact(
  String reply, {
  required String conversationId,
  required String request,
  DateTime? now,
}) {
  final match = _fencedBlock.firstMatch(reply);
  if (match == null) return null;

  final code = match.group(2)!.trim();
  if (code.split('\n').length < _minimumLines) return null;

  final language = match.group(1)!.toLowerCase();
  final whole = isWholeDocument(code);

  // A whole document is always the deliverable, however much prose surrounds
  // it. Anything else has to *be* the reply rather than appear in it.
  if (!whole && code.length < reply.trim().length * _majority) return null;

  final isHtml = whole || language == 'html';
  final isSvg = language == 'svg' || code.trimLeft().startsWith('<svg');

  return Artifact(
    id: 'a${(now ?? DateTime.now()).microsecondsSinceEpoch.toRadixString(36)}',
    conversationId: conversationId,
    title: titleFromArtifact(
      code,
      language: isHtml ? null : language,
      request: request,
    ),
    kind: isHtml
        ? ArtifactKind.html
        : isSvg
            ? ArtifactKind.svg
            : language == 'markdown' || language == 'md'
                ? ArtifactKind.markdown
                : ArtifactKind.code,
    language: language.isEmpty ? null : language,
    versions: [
      ArtifactVersion(content: code, createdAt: now ?? DateTime.now()),
    ],
  );
}
