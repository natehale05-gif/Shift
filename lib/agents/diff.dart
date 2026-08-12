/// A line diff, and the ability to apply part of one.
///
/// Written rather than taken from a package because of the second half: per-hunk
/// accept and reject is the point of the review, and that needs hunks whose
/// boundaries are addressable and reversible, not a rendered patch string. The
/// diff itself is the easy part; being able to keep three changes out of five
/// is what the screen is for.
library;

enum LineKind { kept, added, removed }

class DiffLine {
  final LineKind kind;
  final String text;

  const DiffLine(this.kind, this.text);

  @override
  String toString() => switch (kind) {
        LineKind.kept => ' $text',
        LineKind.added => '+$text',
        LineKind.removed => '-$text',
      };
}

/// A run of changes and the unchanged lines around it.
///
/// [oldStart] and [oldCount] address the *original* file, which is what makes
/// a hunk rejectable: rejecting is emitting those lines unchanged.
class Hunk {
  final int oldStart;
  final int oldCount;
  final int newStart;
  final int newCount;
  final List<DiffLine> lines;

  const Hunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });

  int get added =>
      lines.where((l) => l.kind == LineKind.added).length;

  int get removed =>
      lines.where((l) => l.kind == LineKind.removed).length;

  /// `@@ -3,4 +3,6 @@`, for a header a person can place in the file.
  String get header =>
      '@@ -${oldStart + 1},$oldCount +${newStart + 1},$newCount @@';
}

/// The most cells of the comparison table this will fill before giving up.
///
/// The table is quadratic, so two large files would exhaust memory rather than
/// take a while. Past this the answer is one hunk saying the file was replaced
/// — accurate, less useful, and *bounded*, which beats an app that dies while
/// reviewing a change.
const int kDiffCellLimit = 1000000;

/// Splits like a text file: a trailing newline ends the last line rather than
/// starting an empty one.
List<String> splitLines(String text) {
  if (text.isEmpty) return const [];
  final lines = text.split('\n');
  if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
  return lines;
}

/// The hunks turning [before] into [after], with [context] unchanged lines
/// around each.
List<Hunk> diffHunks(String before, String after, {int context = 3}) {
  final old = splitLines(before);
  final now = splitLines(after);
  final ops = _lineOps(old, now);
  return _group(ops, context: context);
}

/// Rebuilds [before] with only the hunks at [accepted] applied.
///
/// The inverse of the review: accepting every hunk reproduces the agent's file
/// exactly, accepting none reproduces the original exactly. Those two are
/// properties rather than examples, and they are what the tests assert.
String applyHunks(String before, List<Hunk> hunks, Set<int> accepted) {
  final old = splitLines(before);
  final out = <String>[];
  var cursor = 0;

  for (var i = 0; i < hunks.length; i++) {
    final hunk = hunks[i];
    // The untouched stretch before this hunk.
    out.addAll(old.sublist(cursor, hunk.oldStart));
    if (accepted.contains(i)) {
      for (final line in hunk.lines) {
        if (line.kind != LineKind.removed) out.add(line.text);
      }
    } else {
      out.addAll(old.sublist(hunk.oldStart, hunk.oldStart + hunk.oldCount));
    }
    cursor = hunk.oldStart + hunk.oldCount;
  }
  out.addAll(old.sublist(cursor));

  // A file of lines ends with a newline. An empty result is an empty file, not
  // a file containing one blank line.
  return out.isEmpty ? '' : '${out.join('\n')}\n';
}

/// The whole diff as one `DiffLine` list, which is what a renderer walks.
List<DiffLine> _lineOps(List<String> old, List<String> now) {
  // Identical ends are the common case and cost nothing to strip, which keeps
  // the quadratic part to the region that actually differs.
  var head = 0;
  while (head < old.length && head < now.length && old[head] == now[head]) {
    head++;
  }
  var tail = 0;
  while (tail < old.length - head &&
      tail < now.length - head &&
      old[old.length - 1 - tail] == now[now.length - 1 - tail]) {
    tail++;
  }

  final oldMid = old.sublist(head, old.length - tail);
  final nowMid = now.sublist(head, now.length - tail);

  final ops = <DiffLine>[
    for (var i = 0; i < head; i++) DiffLine(LineKind.kept, old[i]),
  ];

  if (oldMid.length * nowMid.length > kDiffCellLimit) {
    // Bounded rather than clever: too large to align, so say what is true —
    // this went, that came.
    ops
      ..addAll([for (final l in oldMid) DiffLine(LineKind.removed, l)])
      ..addAll([for (final l in nowMid) DiffLine(LineKind.added, l)]);
  } else {
    ops.addAll(_align(oldMid, nowMid));
  }

  for (var i = old.length - tail; i < old.length; i++) {
    ops.add(DiffLine(LineKind.kept, old[i]));
  }
  return ops;
}

/// Longest common subsequence, walked back into operations.
List<DiffLine> _align(List<String> old, List<String> now) {
  final n = old.length;
  final m = now.length;
  if (n == 0) return [for (final l in now) DiffLine(LineKind.added, l)];
  if (m == 0) return [for (final l in old) DiffLine(LineKind.removed, l)];

  final table = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      table[i][j] = old[i] == now[j]
          ? table[i + 1][j + 1] + 1
          : (table[i + 1][j] >= table[i][j + 1]
              ? table[i + 1][j]
              : table[i][j + 1]);
    }
  }

  final ops = <DiffLine>[];
  var i = 0;
  var j = 0;
  while (i < n && j < m) {
    if (old[i] == now[j]) {
      ops.add(DiffLine(LineKind.kept, old[i]));
      i++;
      j++;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      // Removal before addition when the two are equally good, so a replaced
      // line reads as `-old` then `+new` rather than the other way round.
      ops.add(DiffLine(LineKind.removed, old[i]));
      i++;
    } else {
      ops.add(DiffLine(LineKind.added, now[j]));
      j++;
    }
  }
  while (i < n) {
    ops.add(DiffLine(LineKind.removed, old[i++]));
  }
  while (j < m) {
    ops.add(DiffLine(LineKind.added, now[j++]));
  }
  return ops;
}

/// Cuts the operation list into hunks, each carrying [context] kept lines.
///
/// Runs closer together than twice the context are one hunk rather than two:
/// two hunks sharing the same lines of context would show them twice, and
/// accepting one would mean deciding about lines the other also claims.
List<Hunk> _group(List<DiffLine> ops, {required int context}) {
  final changed = <int>[
    for (var i = 0; i < ops.length; i++)
      if (ops[i].kind != LineKind.kept) i,
  ];
  if (changed.isEmpty) return const [];

  final ranges = <(int, int)>[];
  var start = changed.first;
  var end = changed.first;
  for (final at in changed.skip(1)) {
    if (at - end > context * 2) {
      ranges.add((start, end));
      start = at;
    }
    end = at;
  }
  ranges.add((start, end));

  final hunks = <Hunk>[];
  for (final (from, to) in ranges) {
    final lo = (from - context).clamp(0, ops.length);
    final hi = (to + context + 1).clamp(0, ops.length);

    // Where this window sits in each file, counted from the operations before
    // it — the only source of truth for both numberings.
    var oldStart = 0;
    var newStart = 0;
    for (var i = 0; i < lo; i++) {
      if (ops[i].kind != LineKind.added) oldStart++;
      if (ops[i].kind != LineKind.removed) newStart++;
    }

    final lines = ops.sublist(lo, hi);
    hunks.add(Hunk(
      oldStart: oldStart,
      oldCount: lines.where((l) => l.kind != LineKind.added).length,
      newStart: newStart,
      newCount: lines.where((l) => l.kind != LineKind.removed).length,
      lines: lines,
    ));
  }
  return hunks;
}
