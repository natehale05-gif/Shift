import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/features/chat/message_actions.dart';
import 'package:shift/features/chat/reply_document.dart';
import 'package:shift/features/chat/turn_controller.dart';

/// Keeping an answer as a document.
void main() {
  String documentXml(List<int> bytes) => utf8.decode(ZipDecoder()
      .decodeBytes(bytes)
      .files
      .firstWhere((f) => f.name == 'word/document.xml')
      .content as List<int>);

  group('what it is called', () {
    test('the question names it, not the answer', () {
      // A reply opens "Sure — here's a summary of the Q3 notes:", which makes
      // a terrible filename. The question is what somebody looks for it under.
      final doc = documentForReply(
        prompt: 'summarise the Q3 notes for me',
        markdown: "Sure — here's a summary of the Q3 notes:\n\nRevenue was up.",
      );

      expect(doc.name, 'summarise-the-q3-notes-for-me.docx');
      expect(doc.name, isNot(contains('sure')));
    });

    test('two questions give two filenames', () {
      // v1 shipped every download as `generated_page.html`, so a second one
      // collided with the first.
      final a = documentForReply(prompt: 'summarise the notes', markdown: 'a');
      final b = documentForReply(prompt: 'draft the email', markdown: 'b');
      expect(a.name, isNot(b.name));
    });

    test('no question at all still produces a usable name', () {
      final doc = documentForReply(prompt: '', markdown: 'text');
      expect(doc.name, endsWith('.docx'));
      expect(doc.name.length, greaterThan('.docx'.length));
    });
  });

  group('what is in it', () {
    test('the markdown is structure, not asterisks', () {
      // The whole reason this is not Copy.
      final xml = documentXml(documentForReply(
        prompt: 'write me a brief',
        markdown: '# Q3\n\n- one\n\n**bold**',
      ).bytes);

      expect(xml, contains('w:val="Heading1"'));
      expect(xml, contains('w:val="ListBullet"'));
      expect(xml, contains('<w:b/>'));
      expect(xml, isNot(contains('**bold**')));
    });

    test('the title inside matches what it is called', () {
      final doc =
          documentForReply(prompt: 'summarise the Q3 notes', markdown: 'Text.');
      final core = utf8.decode(ZipDecoder()
          .decodeBytes(doc.bytes)
          .files
          .firstWhere((f) => f.name == 'docProps/core.xml')
          .content as List<int>);

      expect(core, contains('Summarise the Q3 notes'));
    });
  });

  group('the button', () {
    Widget wrap(TurnController turn, Reply reply) => MultiProvider(
          providers: [ChangeNotifierProvider.value(value: turn)],
          child: MaterialApp(
            theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
            home: Scaffold(body: MessageActions(reply: reply)),
          ),
        );

    /// Runs [body] as a platform that can save.
    ///
    /// Reset inside the body rather than in a tear-down: the framework asserts
    /// this global is unset by the time a test ends, and `addTearDown` runs
    /// too late to satisfy it.
    Future<void> onDesktop(Future<void> Function() body) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await body();
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }

    testWidgets('is offered on an answer and withheld on a failure',
        (t) async {
      final turn = TurnController();
      addTearDown(turn.dispose);

      await onDesktop(() async {
        await t.pumpWidget(wrap(turn, Reply()..write('Some text.')));
        expect(find.byTooltip('Save as a document'), findsOneWidget);

        // Nothing to keep, and offering it would produce an empty document
        // that reads as the app having lost the answer.
        await t.pumpWidget(wrap(turn, Reply()..failure = 'Key rejected.'));
        expect(find.byTooltip('Save as a document'), findsNothing);
      });
    });

    testWidgets('is absent where saving cannot work at all', (t) async {
      // `file_selector` has no iOS or Android implementation, so the dialog
      // never opens and the button does nothing — which on a phone is the only
      // kind of button there is. Absent beats dead.
      final turn = TurnController();
      addTearDown(turn.dispose);

      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        await t.pumpWidget(wrap(turn, Reply()..write('Some text.')));
        expect(find.byTooltip('Save as a document'), findsNothing);
        // And Copy is still there, so the answer is not stranded.
        expect(find.byTooltip('Copy'), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('it clears the touch minimum', (t) async {
      final turn = TurnController();
      addTearDown(turn.dispose);

      await onDesktop(() async {
        await t.pumpWidget(wrap(turn, Reply()..write('Some text.')));
        expect(t.getSize(find.byTooltip('Save as a document')).height,
            greaterThanOrEqualTo(44));
      });
    });
  });

  group('the prompt a reply belongs to', () {
    test('is the message above it', () {
      final turn = TurnController();
      addTearDown(turn.dispose);

      final first = Reply();
      final second = Reply();
      turn.items
        ..add(const UserSaid('the first question'))
        ..add(first)
        ..add(const UserSaid('the second question'))
        ..add(second);

      expect(turn.promptFor(first), 'the first question');
      expect(turn.promptFor(second), 'the second question');
    });

    test('a transcript with no question above answers null, not the wrong one',
        () {
      final turn = TurnController();
      addTearDown(turn.dispose);

      final orphan = Reply();
      turn.items.add(orphan);
      expect(turn.promptFor(orphan), isNull);
    });
  });
}
