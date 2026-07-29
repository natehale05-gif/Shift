import '../studio_composition.dart';

/// An edit demo mode was able to apply: the new HTML, plus a short phrase
/// naming what changed (used in the reply).
typedef MockRevision = ({String html, String summary});

/// Named colours people actually ask for, mapped to the hexes the demo pages
/// use. An explicit `#rrggbb` in the request wins over any of these.
const _namedColors = <String, String>{
  'red': '#FF3B30',
  'orange': '#FF9500',
  'yellow': '#FFCC00',
  'green': '#34C759',
  'teal': '#30B0C7',
  'blue': '#007AFF',
  'navy': '#1B2A4A',
  'indigo': '#5856D6',
  'purple': '#AF52DE',
  'violet': '#AF52DE',
  'pink': '#FF2D55',
  'black': '#1D1D1F',
  'white': '#FFFFFF',
  'grey': '#8E8E93',
  'gray': '#8E8E93',
  'cream': '#F5F4EF',
};

final _hexInRequest = RegExp(r'#([0-9a-fA-F]{6})\b');

String? _colorFrom(String lower) {
  final hex = _hexInRequest.firstMatch(lower);
  if (hex != null) return '#${hex.group(1)!.toUpperCase()}';
  for (final entry in _namedColors.entries) {
    if (RegExp('\\b${entry.key}\\b').hasMatch(lower)) return entry.value;
  }
  return null;
}

/// Replaces the `background:` colour inside one CSS rule — `.cta { … }` or
/// `body { … }` — leaving every other declaration alone.
String? _setRuleBackground(String html, String selector, String hex) {
  final rule = RegExp('(${RegExp.escape(selector)}\\s*\\{)([^}]*)(\\})');
  final match = rule.firstMatch(html);
  if (match == null) return null;
  final body = match.group(2)!;
  if (!body.contains('background:')) return null;
  final updated =
      body.replaceFirst(RegExp(r'background:\s*[^;]+;'), 'background: $hex;');
  return html.replaceRange(
      match.start, match.end, '${match.group(1)}$updated${match.group(3)}');
}

/// Scales the `h1 { font-size: Npx }` value, clamped to something still
/// readable at both ends.
String? _scaleHeading(String html, double factor) {
  final rule = RegExp(r'(h1\s*\{)([^}]*)(\})');
  final match = rule.firstMatch(html);
  if (match == null) return null;
  final body = match.group(2)!;
  final size = RegExp(r'font-size:\s*(\d+(?:\.\d+)?)px').firstMatch(body);
  if (size == null) return null;
  final current = double.parse(size.group(1)!);
  final next = (current * factor).round().clamp(14, 128);
  if (next == current.round()) return null;
  final updated = body.replaceFirst(
      RegExp(r'font-size:\s*\d+(?:\.\d+)?px'), 'font-size: ${next}px');
  return html.replaceRange(
      match.start, match.end, '${match.group(1)}$updated${match.group(3)}');
}

/// The new heading text in "change the heading to X" / "make it say X".
final _headingText = RegExp(
  r'(?:heading|title|headline|h1)\s+(?:to|say|reads?|should say|says)\s+'
  r'''["']?(.+?)["']?\s*$''',
  caseSensitive: false,
);
final _saysText = RegExp(
  r'''(?:make it say|say)\s+["']?(.+?)["']?\s*$''',
  caseSensitive: false,
);

String _escape(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String _appendSection(String html, String label) {
  final block = '<section style="max-width:640px;margin:0 auto;padding:32px 24px;'
      'border-top:1px solid rgba(0,0,0,0.08);text-align:center;'
      'font:400 15px system-ui;color:#6e6e73;">${_escape(label)}</section>';
  final close = html.lastIndexOf('</body>');
  if (close == -1) return '$html\n$block';
  return '${html.substring(0, close)}$block\n${html.substring(close)}';
}

/// Applies a recognisable edit to [html] — the artifact's **current** content,
/// never a fresh template — returning null when demo mode recognises none.
///
/// Demo mode has no model, so it cannot apply arbitrary edits. It does not have
/// to: the pages it writes come from one template with stable anchors, so the
/// handful of edits people try first can be done exactly, and everything else
/// can say so instead of inventing a page.
///
/// Returning null matters as much as the transforms. It used to rebuild the
/// page from the template on every revision, which put the user's request in
/// the `<h1>` ("bakery landing page — make the heading bigger") and silently
/// discarded whatever the previous version had changed.
MockRevision? applyMockRevision(String html, String request) {
  final revision = _match(html, request);
  // A transform that matched the wording but changed nothing — an artifact
  // without the anchor it edits — is a miss, not a success. Claiming "changed
  // the button colour" over identical HTML is the dishonesty this exists to
  // remove, so the invariant is enforced in one place for every branch.
  if (revision == null || revision.html == html) return null;
  return revision;
}

MockRevision? _match(String html, String request) {
  final lower = request.toLowerCase().trim();

  // Heading size before colour: "make the heading bigger" mentions no colour,
  // but "make the heading bigger and red" should read as the size change the
  // sentence leads with.
  if (RegExp(r'\b(heading|title|headline|h1|text|font)\b').hasMatch(lower) &&
      RegExp(r'\b(bigger|larger|big|huge|increase)\b').hasMatch(lower)) {
    final out = _scaleHeading(html, 1.4);
    if (out != null) return (html: out, summary: 'made the heading bigger');
  }
  if (RegExp(r'\b(heading|title|headline|h1|text|font)\b').hasMatch(lower) &&
      RegExp(r'\b(smaller|small|reduce|decrease|shrink)\b').hasMatch(lower)) {
    final out = _scaleHeading(html, 0.7);
    if (out != null) return (html: out, summary: 'made the heading smaller');
  }

  // New heading text.
  final textMatch = _headingText.firstMatch(request.trim()) ??
      (RegExp(r'\b(heading|title|headline)\b').hasMatch(lower)
          ? null
          : _saysText.firstMatch(request.trim()));
  if (textMatch != null) {
    final headline = textMatch.group(1)!.trim().replaceAll(RegExp(r'[.!]+$'), '');
    if (headline.isNotEmpty) {
      return (
        html: embedCopyIntoPage(html, headline: headline),
        summary: 'changed the heading to "$headline"',
      );
    }
  }

  // Colour changes. "background"/"page" targets the body; anything else that
  // names a colour is the call-to-action, which is what "make it red" means on
  // a page whose only strong colour is the button.
  final color = _colorFrom(lower);
  if (color != null) {
    final wantsBackground =
        RegExp(r'\b(background|page|body|backdrop)\b').hasMatch(lower);
    if (wantsBackground) {
      final out = _setRuleBackground(html, 'body', color);
      if (out != null) {
        return (html: out, summary: 'changed the page background');
      }
    }
    final out = _setRuleBackground(html, '.cta', color);
    if (out != null) return (html: out, summary: 'changed the button colour');
  }

  // Add a block.
  final addMatch = RegExp(r'\badd\s+(?:a|an|the)?\s*(footer|section|note|banner)\b')
      .firstMatch(lower);
  if (addMatch != null) {
    final what = addMatch.group(1)!;
    return (
      html: _appendSection(html, 'New $what — added by SHIFT AI.'),
      summary: 'added a $what',
    );
  }

  return null;
}
