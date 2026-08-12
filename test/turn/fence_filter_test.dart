import 'package:flutter_test/flutter_test.dart';
import 'package:shift/turn/fence_filter.dart';

/// Ported with the filter itself, because these are the cases that cost v1
/// releases rather than the ones that are obvious from reading it.
void main() {
  String feedAll(FenceFilter f, List<String> chunks) {
    final out = StringBuffer();
    for (final chunk in chunks) {
      out.write(f.feed(chunk));
    }
    out.write(f.flush());
    return out.toString();
  }

  group('prose streams, code does not', () {
    test('the block is withheld and the prose around it is not', () {
      final f = FenceFilter();
      final prose = feedAll(f, [
        'Here you go:\n',
        '```html\n<h1>Hi</h1>\n```',
        '\nLet me know.',
      ]);

      expect(prose, contains('Here you go'));
      expect(prose, contains('Let me know'));
      expect(prose, isNot(contains('<h1>')));
      expect(f.heldText, contains('<h1>Hi</h1>'));
    });

    test('a fence split across two deltas still closes', () {
      // The chunk-boundary case: a delta can end between the backticks of a
      // marker, and a filter that only looked within a chunk would leak the
      // opening fence as prose and then treat the rest of the page as prose
      // too.
      final f = FenceFilter();
      final prose = feedAll(f, ['before ``', '`html\ncode\nhere\n``', '`\nafter']);

      expect(prose, contains('before'));
      expect(prose, contains('after'));
      expect(prose, isNot(contains('code')));
      expect(f.writingCode, isFalse, reason: 'the block closed');
    });

    test('a lone backtick at the end of the stream is prose after all', () {
      final f = FenceFilter();
      expect(feedAll(f, ['use `code` for that']), 'use `code` for that');
      expect(f.sawFence, isFalse);
    });
  });

  group('withholding is never deletion', () {
    test('held text can be replayed verbatim, markers included', () {
      final f = FenceFilter();
      feedAll(f, ['```dart\nvoid main() {}\n```']);
      expect(f.replayText(), contains('```dart'));
      expect(f.replayText(), contains('void main() {}'));
    });

    test('an unterminated block replays closed', () {
      // The reply was cut off mid-block — the model hit its ceiling. Replaying
      // it with the fence still open renders every later message as code.
      final f = FenceFilter();
      f.feed('```html\n<h1>half a p');
      f.flush();

      expect(f.unterminated, isTrue);
      expect(f.replayText().trimRight(), endsWith('```'));
    });

    test('the tail of a truncated block is kept, not dropped', () {
      final f = FenceFilter();
      f.feed('```html\n<h1>half');
      f.flush();
      expect(f.replayText(), contains('<h1>half'));
    });
  });
}
