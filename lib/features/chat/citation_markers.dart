import '../../turn/turn_event.dart';

/// Splices numbered source markers into [text] at the positions the provider
/// reported.
///
/// Markers rather than a row of chips underneath, because a chip row says
/// *these five pages were consulted* and a marker says *this sentence came
/// from that one*. The second is checkable and the first is not, which is the
/// whole reason [Citation] carries offsets at all.
///
/// Rendered as an ordinary markdown link — `[¹](url)` — so the existing
/// markdown view draws and handles it with nothing new. No inline widget, no
/// second text pipeline.
///
/// **Walked in descending order of offset, and that is load-bearing.** Every
/// insertion shifts everything after it, so splicing front-to-back would land
/// the second marker further and further from the sentence it belongs to.
/// Going backwards leaves every remaining offset still valid.
String withCitationMarkers(String text, List<Citation> citations) {
  final spans = [
    for (var i = 0; i < citations.length; i++)
      if (citations[i].hasSpan) (index: i, at: citations[i].end!)
  ]
    // An offset past the end of the text is a provider disagreeing with itself
    // about what it sent. Dropped rather than clamped: a marker at the end of
    // the reply claims a sentence it may have nothing to do with.
    ..removeWhere((s) => s.at < 0 || s.at > text.length)
    ..sort((a, b) => b.at.compareTo(a.at));

  var out = text;
  for (final span in spans) {
    final marker = '[${_superscript(span.index + 1)}]'
        '(${citations[span.index].url})';
    out = out.replaceRange(span.at, span.at, marker);
  }
  return out;
}

/// Whether any of these can be shown inline at all.
bool anyInline(List<Citation> citations) => citations.any((c) => c.hasSpan);

/// Sources in the order their markers number them, deduplicated by URL.
///
/// The rail and the markers have to agree — a marker reading ³ next to a rail
/// whose third row is a different page is worse than no marker — so both take
/// their numbering from this one list.
List<Citation> railOrder(List<Citation> citations) {
  final seen = <String>{};
  return [
    for (final c in citations)
      if (seen.add(c.url.toString())) c,
  ];
}

/// `1` → `¹`. Superscripts because a bracketed `[1]` in prose reads as part of
/// the sentence, and a raised digit reads as an annotation about it.
String _superscript(int n) =>
    n.toString().split('').map((d) => _digits[d] ?? d).join();

const _digits = {
  '0': '⁰',
  '1': '¹',
  '2': '²',
  '3': '³',
  '4': '⁴',
  '5': '⁵',
  '6': '⁶',
  '7': '⁷',
  '8': '⁸',
  '9': '⁹',
};
