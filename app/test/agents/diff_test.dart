import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/agents/diff.dart';

/// The diff, and the two properties the review rests on.
///
/// Most of this suite is not examples. Accepting every hunk must reproduce the
/// agent's file *exactly*, and accepting none must reproduce the original
/// *exactly* — for any pair of files, not for the three I thought of. Those two
/// are checked against random edits, because a per-hunk apply that is subtly
/// wrong loses someone's work while looking like it worked.
void main() {
  group('what changed', () {
    test('an unchanged file has no hunks', () {
      expect(diffHunks('a\nb\n', 'a\nb\n'), isEmpty);
    });

    test('a replaced line reads as removed then added', () {
      final hunk = diffHunks('a\nb\nc\n', 'a\nB\nc\n').single;
      expect(hunk.lines.map((l) => l.toString()),
          [' a', '-b', '+B', ' c']);
      expect(hunk.added, 1);
      expect(hunk.removed, 1);
    });

    test('changes far apart are separate hunks', () {
      final before = [for (var i = 0; i < 40; i++) 'line $i'].join('\n');
      final after = before
          .replaceFirst('line 1', 'LINE 1')
          .replaceFirst('line 35', 'LINE 35');

      expect(diffHunks('$before\n', '$after\n'), hasLength(2));
    });

    test('changes close together are one hunk, not two overlapping ones', () {
      // Two hunks sharing context would show those lines twice, and accepting
      // one would mean deciding about lines the other also claims.
      final before = [for (var i = 0; i < 20; i++) 'line $i'].join('\n');
      final after = before
          .replaceFirst('line 5', 'LINE 5')
          .replaceFirst('line 8', 'LINE 8');

      expect(diffHunks('$before\n', '$after\n'), hasLength(1));
    });

    test('the header places the hunk in the file', () {
      final before = [for (var i = 0; i < 20; i++) 'line $i'].join('\n');
      final after = before.replaceFirst('line 10', 'LINE 10');
      final hunk = diffHunks('$before\n', '$after\n').single;

      // Line 11 in one-based counting, seven lines of window.
      expect(hunk.header, '@@ -8,7 +8,7 @@');
    });

    test('a new file is all additions', () {
      final hunk = diffHunks('', 'a\nb\n').single;
      expect(hunk.removed, 0);
      expect(hunk.added, 2);
    });

    test('an emptied file is all removals', () {
      final hunk = diffHunks('a\nb\n', '').single;
      expect(hunk.added, 0);
      expect(hunk.removed, 2);
    });

    test('a trailing newline ends the last line, it does not start a new one',
        () {
      expect(splitLines('a\nb\n'), ['a', 'b']);
      expect(splitLines(''), isEmpty);
      // A file that genuinely ends with a blank line still has one.
      expect(splitLines('a\n\n'), ['a', '']);
    });

    test('two files too large to align still produce a bounded answer', () {
      // Quadratic means "exhausts memory", not "takes a while". Past the limit
      // the answer is "this went, that came" — less useful, and not a crash
      // while someone is reviewing their work.
      //
      // The files here *do* have lines in common, which is what makes the
      // assertion able to fail: aligning them would find that half the lines
      // survived and report `-1050 +0`. Written first with two files sharing
      // nothing, it passed with the limit disabled — both paths give the same
      // answer when there is nothing to align.
      const rows = 2100;
      final old = [for (var i = 0; i < rows; i++) 'line $i'];
      final now = [for (var i = 0; i < rows; i += 2) 'line $i'];
      expect((rows - 1) * (now.length - 1), greaterThan(kDiffCellLimit),
          reason: 'the fixture has to be past the limit or this proves nothing');

      final hunks = diffHunks('${old.join('\n')}\n', '${now.join('\n')}\n');
      expect(hunks, hasLength(1));
      // Everything after the one shared opening line, both ways.
      expect(hunks.single.removed, rows - 1);
      expect(hunks.single.added, now.length - 1);
    });
  });

  group('keeping some of it', () {
    const before = 'one\ntwo\nthree\nfour\nfive\nsix\nseven\n';

    test('accepting everything is the agent\'s file', () {
      const after = 'ONE\ntwo\nthree\nfour\nfive\nsix\nSEVEN\n';
      final hunks = diffHunks(before, after);

      expect(applyHunks(before, hunks, {for (var i = 0; i < hunks.length; i++) i}),
          after);
    });

    test('accepting nothing is the original', () {
      const after = 'ONE\ntwo\nthree\nfour\nfive\nsix\nSEVEN\n';
      final hunks = diffHunks(before, after);

      expect(applyHunks(before, hunks, const {}), before);
    });

    test('accepting one of two keeps exactly that one', () {
      const after = 'ONE\ntwo\nthree\nfour\nfive\nsix\nSEVEN\n';
      final hunks = diffHunks(before, after, context: 1);
      expect(hunks, hasLength(2));

      expect(applyHunks(before, hunks, const {0}),
          'ONE\ntwo\nthree\nfour\nfive\nsix\nseven\n');
      expect(applyHunks(before, hunks, const {1}),
          'one\ntwo\nthree\nfour\nfive\nsix\nSEVEN\n');
    });

    test('an accepted insertion lands where it was written', () {
      const after = 'one\ntwo\nTWO AND A HALF\nthree\nfour\nfive\nsix\nseven\n';
      final hunks = diffHunks(before, after);

      expect(applyHunks(before, hunks, const {0}), after);
    });
  });

  group('for any pair of files', () {
    // The properties, against edits I did not choose. A per-hunk apply that is
    // subtly wrong loses someone's work while looking like it worked, and no
    // number of hand-written examples rules that out.
    test('all-accepted round-trips and none-accepted restores', () {
      final random = Random(20260810);

      for (var trial = 0; trial < 200; trial++) {
        final lines = [
          for (var i = 0; i < random.nextInt(30) + 1; i++) 'line $i',
        ];
        final edited = <String>[];
        for (final line in lines) {
          switch (random.nextInt(6)) {
            case 0:
              break; // deleted
            case 1:
              edited.add(line.toUpperCase());
            case 2:
              edited
                ..add('inserted before $line')
                ..add(line);
            default:
              edited.add(line);
          }
        }
        if (random.nextBool()) edited.add('appended');

        final before = lines.isEmpty ? '' : '${lines.join('\n')}\n';
        final after = edited.isEmpty ? '' : '${edited.join('\n')}\n';
        final hunks = diffHunks(before, after);
        final all = {for (var i = 0; i < hunks.length; i++) i};

        expect(applyHunks(before, hunks, all), after,
            reason: 'trial $trial: accepting everything must be the new file');
        expect(applyHunks(before, hunks, const {}), before,
            reason: 'trial $trial: accepting nothing must be the old file');
      }
    });

    test('accepting a subset never invents a line neither file had', () {
      final random = Random(11);

      for (var trial = 0; trial < 100; trial++) {
        final lines = [for (var i = 0; i < 20; i++) 'line $i'];
        final edited = [
          for (final line in lines)
            if (random.nextInt(4) != 0)
              random.nextInt(3) == 0 ? '$line changed' : line,
        ];
        final before = '${lines.join('\n')}\n';
        final after = edited.isEmpty ? '' : '${edited.join('\n')}\n';
        final hunks = diffHunks(before, after);
        if (hunks.isEmpty) continue;

        final picked = {
          for (var i = 0; i < hunks.length; i++)
            if (random.nextBool()) i,
        };
        final known = {...splitLines(before), ...splitLines(after)};

        for (final line in splitLines(applyHunks(before, hunks, picked))) {
          expect(known, contains(line), reason: 'trial $trial');
        }
      }
    });
  });
}
