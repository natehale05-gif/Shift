import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/turn/fence_filter.dart';

/// Runs [chunks] through a filter and returns (emitted prose, held text).
(String, String) run(List<String> chunks) {
  final filter = FenceFilter();
  final prose = StringBuffer();
  for (final chunk in chunks) {
    prose.write(filter.feed(chunk));
  }
  prose.write(filter.flush());
  return (prose.toString(), filter.heldText);
}

void main() {
  test('prose with no fence passes straight through', () {
    final (prose, held) = run(['The capital ', 'of France ', 'is Paris.']);
    expect(prose, 'The capital of France is Paris.');
    expect(held, isEmpty);
  });

  test('a fenced block is withheld and the prose around it is kept', () {
    final (prose, held) = run([
      'Here you go:\n\n',
      '```html\n<!DOCTYPE html>\n<html></html>\n```',
      '\n\nSave it as index.html.',
    ]);
    expect(prose, 'Here you go:\n\n\n\nSave it as index.html.');
    expect(held, '```html\n<!DOCTYPE html>\n<html></html>\n```');
  });

  test('a marker split across chunks is still recognised', () {
    // The failure this class exists to survive: a delta boundary can land
    // between the backticks of a fence.
    final (prose, held) = run(['Here:\n', '`', '`', '`html\n<p>hi</p>\n', '``', '`']);
    expect(prose, 'Here:\n');
    expect(held, '```html\n<p>hi</p>\n```');
  });

  test('a marker split one backtick at a time, mid-word', () {
    final (prose, held) = run(['a', '`', '`', '`', 'x\ncode\n', '`', '`', '`', 'b']);
    expect(prose, 'ab');
    expect(held, '```x\ncode\n```');
  });

  test('inline single backticks are prose, not fences', () {
    final (prose, held) =
        run(['Add ', '`display: flex`', ' to the row.']);
    expect(prose, 'Add `display: flex` to the row.');
    expect(held, isEmpty);
  });

  test('two backticks are prose too', () {
    final (prose, held) = run(['use ``literal`` here']);
    expect(prose, 'use ``literal`` here');
    expect(held, isEmpty);
  });

  test('trailing backticks left dangling become prose', () {
    // Never swallow characters: an unterminated run of backticks at the end
    // of a reply was never a marker.
    final (prose, held) = run(['almost a fence ``']);
    expect(prose, 'almost a fence ``');
    expect(held, isEmpty);
  });

  test('an unterminated fence keeps its content held', () {
    // A truncated reply. The content is still replayable rather than lost.
    final (prose, held) = run(['Here:\n```html\n<html>']);
    expect(prose, 'Here:\n');
    expect(held, '```html\n<html>');
    expect(FenceFilter().sawFence, isFalse);
  });

  test('several blocks are all held, in order', () {
    final (prose, held) = run([
      'first:\n```sh\nnpm i\n```\nthen:\n```html\n<html></html>\n```\ndone',
    ]);
    expect(prose, 'first:\n\nthen:\n\ndone');
    expect(held, '```sh\nnpm i\n```\n```html\n<html></html>\n```');
  });

  test('a one-character-at-a-time stream behaves identically', () {
    const reply = 'Look:\n```html\n<html>hi</html>\n```\nDone.';
    final (prose, held) = run(reply.split(''));
    expect(prose, 'Look:\n\nDone.');
    expect(held, '```html\n<html>hi</html>\n```');
  });

  test('sawFence reports whether anything was withheld', () {
    final plain = FenceFilter()..feed('just prose');
    expect(plain.sawFence, isFalse);

    final fenced = FenceFilter()..feed('```\ncode\n```');
    expect(fenced.sawFence, isTrue);
  });

  test('a stream that ends inside a fence reports it', () {
    final cut = FenceFilter()..feed('Here:\n```html\n<html>');
    cut.flush();
    expect(cut.unterminated, isTrue);

    final whole = FenceFilter()..feed('Here:\n```html\n<html></html>\n```');
    whole.flush();
    expect(whole.unterminated, isFalse);
  });

  test('replaying a truncated block closes the fence', () {
    // Markdown with an open fence renders every following message as code,
    // so replaying the held text verbatim would swallow the rest of the
    // conversation into one grey box.
    final cut = FenceFilter()..feed('Here:\n```html\n<html>');
    cut.flush();
    expect(cut.replayText(), '```html\n<html>\n```');
  });

  test('replaying a complete block leaves it exactly as it arrived', () {
    final whole = FenceFilter()..feed('```html\n<html></html>\n```');
    whole.flush();
    expect(whole.replayText(), '```html\n<html></html>\n```');
  });

  test('replaying nothing held is empty, not a bare fence', () {
    final plain = FenceFilter()..feed('just prose');
    plain.flush();
    expect(plain.replayText(), isEmpty);
  });
}
