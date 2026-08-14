import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/note_store.dart';
import 'package:shift/features/notes/note_cleaner.dart';
import 'package:shift/features/notes/notes_surface.dart';

/// The editor, reached the way the app reaches it.
///
/// **Pushed onto a real Navigator from the list**, rather than pumped on its
/// own. That is the whole point of this file: the first version of this screen
/// saved in `dispose` through `context.read`, which throws once the route has
/// popped — so a note was written, the screen closed, and the list came back
/// empty. A test that hands the screen its store directly passes anyway, which
/// is why this one does not.
void main() {
  late Directory dir;
  late NoteStore notes;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-note-screen');
    final kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    notes = NoteStore(kv);
    await notes.load();
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// Advances the fake clock **and** lets the real writes land.
  ///
  /// Saving touches a real file, and a `dart:io` future started under the test
  /// clock never resolves — the first version of this file simply hung. Pumping
  /// inside [WidgetTester.runAsync] is what lets both make progress.
  /// Two clocks, in this order and not the other.
  ///
  /// The debounce is a `Timer`, which only fires when the **test** clock is
  /// advanced — and `pump` inside [WidgetTester.runAsync] does not advance it.
  /// The save it then starts is real `dart:io`, which only finishes in **real**
  /// time. So: pump first, then hand the loop back.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();
  }

  /// Seeds a note the way the store does, outside the test clock — an awaited
  /// real write inside it never resolves, which hung this file once.
  Future<void> seed(WidgetTester tester, String id, String body) =>
      tester.runAsync(() => notes.save(id, body));

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: notes),
        ChangeNotifierProvider(create: (_) => NoteCleaner()),
      ],
      child: MaterialApp(
        theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
        home: const NotesSurface(),
      ),
    ));
    await settle(tester);
  }

  Future<void> openNew(WidgetTester tester) async {
    await tester.tap(find.text('New note'));
    await settle(tester);
  }

  Future<void> goBack(WidgetTester tester) async {
    await tester.tap(find.byType(BackButton));
    await settle(tester);
  }

  testWidgets('a note written and closed is in the list', (tester) async {
    await pump(tester);
    await openNew(tester);

    await tester.enterText(
        find.byType(TextField), 'Sprint planning\nship the notes mode');
    await goBack(tester);

    expect(notes.index, hasLength(1));
    expect(notes.index.single.title, 'Sprint planning');
    expect(find.text('Sprint planning'), findsOneWidget);
  });

  testWidgets('it is on disk before the screen closes', (tester) async {
    // The other half: a killed app must not lose what was typed either.
    await pump(tester);
    await openNew(tester);

    await tester.enterText(find.byType(TextField), 'Half a thought');
    await settle(tester);

    expect(notes.index.single.title, 'Half a thought',
        reason: 'saved while still open, not only on the way out');
  });

  testWidgets('opening a note and changing nothing adds no row',
      (tester) async {
    await pump(tester);
    await openNew(tester);
    await goBack(tester);

    expect(notes.index, isEmpty,
        reason: 'an empty note is not a note, and an "Untitled" row for every '
            'accidental tap is a list nobody can use');
  });

  testWidgets('reopening shows what was written', (tester) async {
    await seed(tester, 'n1', 'Buy milk\nand bread');
    await pump(tester);

    await tester.tap(find.text('Buy milk'));
    await settle(tester);

    expect(find.text('Buy milk\nand bread'), findsOneWidget);
  });

  testWidgets('emptying a note removes it', (tester) async {
    await seed(tester, 'n1', 'Gone soon');
    await pump(tester);
    await tester.tap(find.text('Gone soon'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), '');
    await goBack(tester);

    expect(notes.index, isEmpty);
  });
}
