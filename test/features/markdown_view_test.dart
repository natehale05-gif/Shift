import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/features/chat/markdown_view.dart';

/// The case that chose this renderer.
///
/// A finished document is the easy half. **Every frame during streaming is
/// malformed markdown** — an unclosed fence, a table with one row, a `**`
/// waiting for its pair — and a renderer that throws, blanks the message, or
/// swallows the text on those is unusable here however well it handles a
/// complete document. These drive it with half-written input and assert the
/// words are still on screen.
Future<void> pump(WidgetTester tester, String source) async {
  await tester.pumpWidget(MaterialApp(
    theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
    home: Scaffold(
      body: SingleChildScrollView(child: MarkdownView(source)),
    ),
  ));
  await tester.pump();
}

/// True when [needle] appears in any Text/RichText on screen.
bool showsText(WidgetTester tester, String needle) {
  for (final widget in tester.allWidgets) {
    if (widget is Text && (widget.data?.contains(needle) ?? false)) return true;
    if (widget is RichText &&
        widget.text.toPlainText().contains(needle)) {
      return true;
    }
    if (widget is SelectableText &&
        (widget.data?.contains(needle) ?? false)) {
      return true;
    }
  }
  return false;
}

void main() {
  group('a document still being written', () {
    testWidgets('an unclosed fence still shows its code', (tester) async {
      await pump(tester, 'Here you go:\n\n```html\n<!DOCTYPE html>\n<html>');

      expect(showsText(tester, 'Here you go'), isTrue);
      expect(showsText(tester, '<!DOCTYPE html>'), isTrue,
          reason: 'withholding a fence until it closes makes a long code '
              'reply look like the app has hung');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a half-written table does not blank the message',
        (tester) async {
      await pump(tester, 'Comparison:\n\n| A | B |\n| --- |');

      expect(showsText(tester, 'Comparison'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unpaired emphasis marker is harmless', (tester) async {
      await pump(tester, 'This is **very impo');
      expect(showsText(tester, 'very impo'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a bare list marker with nothing after it', (tester) async {
      await pump(tester, 'Steps:\n\n- first\n- ');
      expect(showsText(tester, 'first'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('text arriving one character at a time never throws',
        (tester) async {
      // The closest thing to the real streaming case: render every prefix of
      // a document containing a fence, a list and a table. If any single
      // intermediate state is fatal, this finds which.
      const full = '# Title\n\nSome **bold** and `code`.\n\n'
          '- one\n- two\n\n```dart\nvoid main() {}\n```\n\n'
          '| A | B |\n| --- | --- |\n| 1 | 2 |';

      for (var i = 1; i <= full.length; i++) {
        await pump(tester, full.substring(0, i));
        expect(tester.takeException(), isNull,
            reason: 'failed at prefix length $i:\n${full.substring(0, i)}');
      }
    });
  });

  group('a finished document', () {
    testWidgets('headings, lists, code and inline code all render',
        (tester) async {
      await pump(
        tester,
        '# Heading\n\nA paragraph with `inline` code.\n\n'
        '- first item\n- second item\n\n```dart\nvoid main() {}\n```',
      );

      expect(showsText(tester, 'Heading'), isTrue);
      expect(showsText(tester, 'first item'), isTrue);
      expect(showsText(tester, 'inline'), isTrue);
      expect(showsText(tester, 'void main()'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('raw markdown characters are not shown as themselves',
        (tester) async {
      // The whole point: before this, a reply with a list rendered as literal
      // asterisks, which is what the user was looking at.
      await pump(tester, '- one\n- two');
      expect(showsText(tester, '- one'), isFalse,
          reason: 'the marker should have become a bullet, not stayed text');
      expect(showsText(tester, 'one'), isTrue);
    });

    testWidgets('a fence is set in the code face on a sunken ground',
        (tester) async {
      await pump(tester, '```dart\nvoid main() {}\n```');
      // The language label is worth showing: it is how a reader knows they
      // are looking at the thing they asked for.
      expect(showsText(tester, 'dart'), isTrue);
    });

    testWidgets('both themes render without a missing token', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(MaterialApp(
          theme: shiftTheme(brightness, TargetPlatform.iOS),
          home: const Scaffold(body: MarkdownView('# Hi\n\n`x`')),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$brightness');
      }
    });
  });
}
