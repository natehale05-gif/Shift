import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/artifact.dart';
import 'package:shift/data/artifact_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/artifacts/artifact_panel.dart';
import 'package:shift/features/chat/chat_surface.dart';
import 'package:shift/features/chat/composer.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/features/artifacts/sandbox_view_stub.dart'
    if (dart.library.js_interop) 'package:shift/features/artifacts/sandbox_view_web.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-artifact');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Artifact page({int versions = 1}) => Artifact(
        id: 'a1',
        conversationId: 'c1',
        title: 'Coffee shop',
        kind: ArtifactKind.html,
        versions: [
          for (var i = 0; i < versions; i++)
            ArtifactVersion(
              content: '<html><body><h1>v${i + 1}</h1></body></html>',
              createdAt: DateTime(2026, 1, i + 1),
            ),
        ],
      );

  Widget host(Artifact artifact) => MaterialApp(
        theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
        home: Scaffold(body: ArtifactPanel(artifact: artifact)),
      );

  testWidgets('the version navigator is absent at one version', (t) async {
    // Chrome that can never be used, on the surface with the least room to
    // spare. v1 grew three rows of it and left half a phone for the page.
    await t.pumpWidget(host(page()));
    expect(find.textContaining('v1/'), findsNothing);

    await t.pumpWidget(host(page(versions: 2)));
    expect(find.text('v2/2'), findsOneWidget,
        reason: 'and it opens on the newest, not on the one just replaced');
  });

  testWidgets('code and preview are two states of one control', (t) async {
    await t.pumpWidget(host(page()));

    // Off-web there is no frame, so the preview says where it opens instead of
    // showing a rectangle that never fills in.
    expect(find.byTooltip('Code'), findsOneWidget);
    await t.tap(find.byTooltip('Code'));
    await t.pumpAndSettle();

    expect(find.textContaining('<h1>v1</h1>'), findsOneWidget);
    expect(find.byTooltip('Preview'), findsOneWidget);
  });

  testWidgets('something a browser cannot render offers no preview', (t) async {
    // A Preview tab that can only ever show source is a control lying about
    // having two states.
    await t.pumpWidget(host(Artifact(
      id: 'a2',
      conversationId: 'c1',
      title: 'helper.py',
      kind: ArtifactKind.code,
      language: 'python',
      versions: [
        ArtifactVersion(content: 'def go():\n  pass\n', createdAt: DateTime(2026)),
      ],
    )));

    expect(find.byTooltip('Code'), findsNothing);
    expect(find.byTooltip('Preview'), findsNothing);
    expect(find.textContaining('def go()'), findsOneWidget);
  });

  testWidgets('the panel offers a way to keep the thing it is showing',
      (t) async {
    // Deferred out of N2b because there was no way to save anything off-web.
    // There is now, and a page you can preview but not keep is a deliverable
    // only in the sense that you can look at it.
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await t.pumpWidget(host(page()));

      expect(find.byTooltip('Save'), findsOneWidget);
      expect(find.byTooltip('Copy'), findsOneWidget);
    } finally {
      // Reset inside the body: the framework asserts this global is unset by
      // the time a test ends, and `addTearDown` runs too late for it.
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('and withholds it where saving cannot work', (t) async {
    // `file_selector` has no iOS or Android implementation, so the dialog
    // never opens and the button does nothing. Copy still works, so the page
    // is not stranded.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await t.pumpWidget(host(page()));

      expect(find.byTooltip('Save'), findsNothing);
      expect(find.byTooltip('Copy'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('every control clears the tap-target minimum', (t) async {
    await t.pumpWidget(host(page(versions: 2)));

    final buttons = find.byType(IconButton);
    expect(buttons, findsWidgets);
    for (var i = 0; i < buttons.evaluate().length; i++) {
      final size = t.getSize(buttons.at(i));
      expect(size.height, greaterThanOrEqualTo(kMinTouchTarget),
          reason: 'control $i is ${size.height} tall');
    }
  });

  testWidgets('a wide window keeps the conversation beside the panel',
      (t) async {
    // Found by looking at the real build: the threshold was the chat column's
    // comfortable *maximum*, so a 1300pt window went full-screen with 1040pt
    // going spare — taking the transcript and the composer with it, leaving no
    // way to reply to the thing being previewed.
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);

    for (final (width, together) in [(1040.0, true), (700.0, false)]) {
      t.view.physicalSize = Size(width, 900);
      await t.pumpWidget(MaterialApp(
        theme: shiftTheme(Brightness.light, TargetPlatform.linux),
        home: Scaffold(
          body: MultiProvider(
            providers: [ChangeNotifierProvider.value(value: _seeded())],
            child: const ChatSurface(),
          ),
        ),
      ));
      await t.pumpAndSettle();

      // Asserted on geometry, not on what is in the tree: the narrow layout
      // stacks the panel *over* the conversation rather than replacing it, so
      // the composer is still built either way — which is deliberate, since it
      // keeps scroll position and draft text across opening the panel.
      final panel = t.getSize(find.byType(ArtifactPanel)).width;
      expect(panel, together ? ArtifactPanel.width : width,
          reason: 'at ${width}pt the panel should '
              '${together ? "sit beside the conversation" : "cover it"}');

      if (together) {
        expect(t.getSize(find.byType(Composer)).width, greaterThan(0),
            reason: 'there has to be a way to reply to what is being shown');
      }
    }
  });

  test('the sandbox arm matches the platform', () {
    // Choosing the wrong arm raises nothing — the preview simply never
    // renders — so it is asserted rather than assumed. This runs on the VM,
    // where the stub is correct; the web build is covered by the same
    // constant being checked in a browser test.
    expect(sandboxKind, 'unavailable');
  });

  group('storage', () {
    Future<ArtifactStore> open() async {
      final store = ArtifactStore(KvStore(path: '${dir.path}/s.json'));
      await store.load();
      return store;
    }

    test('an artifact survives a reload with its versions', () async {
      final first = await open();
      await first.save(page(versions: 2));

      final restored = (await open()).forConversation('c1').single;
      expect(restored.title, 'Coffee shop');
      expect(restored.versions, hasLength(2));
      expect(restored.latest.content, contains('v2'));
    });

    test('saving again replaces rather than duplicates', () async {
      // Replacing by id is what makes a revision a new *version* of the thing
      // on screen instead of a second near-identical entry beside it.
      final store = await open();
      await store.save(page());
      await store.save(page(versions: 2));

      final all = store.forConversation('c1');
      expect(all, hasLength(1));
      expect(all.single.versions, hasLength(2));
    });

    test('a corrupt row costs its artifacts, not the conversation', () async {
      await File('${dir.path}/s.json')
          .writeAsString('{"artifacts.c1":"not json"}');
      expect((await open()).forConversation('c1'), isEmpty);
    });
  });
}

/// A controller holding one finished exchange with an artifact open.
TurnController _seeded() {
  final turn = TurnController(executors: () => const {});
  final artifact = Artifact(
    id: 'a1',
    conversationId: 'c1',
    title: 'Coffee shop',
    kind: ArtifactKind.html,
    versions: [
      ArtifactVersion(content: '<html><body>hi</body></html>',
          createdAt: DateTime(2026)),
    ],
  );
  turn.items
    ..add(const UserSaid('build me a page'))
    ..add(Reply()
      ..write('Here it is.')
      ..artifactId = artifact.id
      ..done = true);
  turn.produced.add(artifact);
  turn.showArtifact(artifact.id);
  return turn;
}
