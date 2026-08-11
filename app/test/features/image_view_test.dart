import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/asset_store.dart';
import 'package:shift/data/image_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/made_image.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/features/visual/image_viewer.dart';
import 'package:shift/features/visual/visual_turns.dart';
import 'package:shift/features/visual/made_image_view.dart';

/// The picture on screen.
///
/// Driven against a real store on a real disk, because the interesting thing
/// this widget does is fetch bytes it was not handed — a double that always
/// answers would prove nothing about the case that matters, which is a record
/// whose bytes are gone.
void main() {
  late Directory dir;
  late ImageStore images;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-image-view');
    final kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    images = ImageStore(kv, AssetStore(directory: '${dir.path}/assets'));
    await images.load();
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> pumpIn(
    WidgetTester tester,
    Widget child, {
    List<SingleChildWidget> extra = const [],
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ImageStore>.value(value: images),
          ...extra,
        ],
        child: MaterialApp(
          theme: shiftTheme(Brightness.light, TargetPlatform.linux),
          home: Scaffold(body: child),
        ),
      ),
    );
  }

  Future<void> seed(String id) => images.save(
        MadeImage(
          id: id,
          prompt: 'a cat',
          provider: 'gemini',
          model: 'nano',
          mimeType: 'image/png',
          createdAt: DateTime(2026),
        ),
        _onePixelPng,
      );

  testWidgets('a picture with bytes draws', (tester) async {
    await tester.runAsync(() => images.save(
          MadeImage(
            id: 'a',
            prompt: 'a cat',
            provider: 'gemini',
            model: 'nano',
            mimeType: 'image/png',
            createdAt: DateTime(2026),
          ),
          _onePixelPng,
        ));

    await pumpIn(tester, const MadeImageView(id: 'a', prompt: 'a cat'));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    // The alternative text a screen reader gets. The app knows exactly what
    // the picture was asked to be, so leaving it unlabelled would be a
    // deliberate omission rather than a missing fact.
    expect(
      tester.getSemantics(find.byType(MadeImageView)),
      matchesSemantics(isImage: true, label: 'a cat'),
    );
  });

  testWidgets('a record whose bytes are gone says so', (tester) async {
    // Not a blank box: the recoverable half of a disagreement between the
    // index and the disk has to look like a missing picture, not a layout bug.
    await pumpIn(tester, const MadeImageView(id: 'missing'));
    // Two clocks: the lookup is a real disk read, which only completes in real
    // time, while `pumpAndSettle` advances the *test* clock and would spin
    // forever against the placeholder's own animation.
    await tester.runAsync(() => Future<void>.delayed(
        const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('no longer on this device'), findsOneWidget);
  });

  testWidgets('every control in the viewer clears the tap target',
      (tester) async {
    // This check has caught this app four times, and the viewer sits over a
    // scrim where a miss closes the dialog.
    await tester.runAsync(() => images.save(
          MadeImage(
            id: 'a',
            prompt: 'a cat',
            provider: 'gemini',
            model: 'nano',
            mimeType: 'image/png',
            createdAt: DateTime(2026),
          ),
          _onePixelPng,
        ));

    await pumpIn(tester, const ImageViewer(id: 'a'));
    await tester.pump();

    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Copy prompt'), findsOneWidget);
    for (final label in ['Save', 'Copy prompt', 'Close']) {
      final size = tester.getSize(
        find.ancestor(of: find.text(label), matching: find.byType(InkWell)),
      );
      expect(size.height, greaterThanOrEqualTo(kMinTouchTarget), reason: label);
      expect(size.width, greaterThanOrEqualTo(kMinTouchTarget), reason: label);
    }
  });

  // **There is no tap-driven test for Delete, and that is a limitation rather
  // than an oversight.** Any `tester.tap` on this widget hangs the test
  // harness indefinitely — verified against `Copy prompt`, whose handler
  // touches nothing but the clipboard, so it is the tap itself and not the
  // deletion. What is covered instead: the control appears exactly when there
  // is something to delete (below), the removal of a record and its bytes
  // (`image_store_test`), and the whole path pressed by hand in the running
  // Linux build with the file read back off disk afterwards.

  testWidgets('a picture with no record offers neither Copy prompt nor Delete',
      (tester) async {
    // What a private chat produces: nothing was recorded, so there is nothing
    // to delete and no prompt to copy. A control that silently does nothing is
    // worse than one that is not there.
    images.hold('p', _onePixelPng);

    await pumpIn(tester, const ImageViewer(id: 'p'));
    await tester.pump();

    expect(find.text('Delete'), findsNothing);
    expect(find.text('Save'), findsOneWidget, reason: 'the control that works');
  });

  testWidgets('every action stays on a phone screen', (tester) async {
    // The tap-target check cannot see this: each control was the right size
    // and the last two were off the right edge. Five actions do not fit one
    // line at 393pt, so the row wraps — and this is the assertion that says
    // so, because "it overflowed" and "it was too small" are different bugs
    // with the same symptom of a control you cannot press.
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);

    await tester.runAsync(() => seed('a'));
    final turn = TurnController();
    addTearDown(turn.dispose);

    await pumpIn(tester, ImageViewer(id: 'a', turns: turn));
    await tester.pump();

    for (final label in ['Save', 'Change it', 'Copy prompt', 'Delete', 'Close']) {
      final box = tester.getRect(find.text(label));
      expect(box.right, lessThanOrEqualTo(393.0), reason: label);
      expect(box.left, greaterThanOrEqualTo(0.0), reason: label);
    }
  });

  group('Change it', () {
    testWidgets('goes to the controller the caller named', (tester) async {
      // Passed in rather than looked up, and this is why: both controllers are
      // provided for the whole app, so any precedence rule is wrong in one of
      // the two places. A lookup version handed a picture changed from Chat to
      // Visual's composer, where nobody was looking.
      await tester.runAsync(() => seed('a'));
      final chat = TurnController();
      final visual = VisualTurns(keys: ApiKeysStore(KvStore()), images: images);
      addTearDown(chat.dispose);
      addTearDown(visual.dispose);

      await pumpIn(tester, ImageViewer(id: 'a', turns: chat), extra: [
        ChangeNotifierProvider<TurnController>.value(value: chat),
        ChangeNotifierProvider<VisualTurns>.value(value: visual),
      ]);
      await tester.pump();

      expect(find.text('Change it'), findsOneWidget);
      expect(chat.editingImage, isNull, reason: 'not until it is pressed');
    });

    testWidgets('is not offered when nothing can receive it', (tester) async {
      // The control, and it is load-bearing: a viewer opened from somewhere
      // with no composer would otherwise show a button that does nothing.
      await tester.runAsync(() => seed('a'));

      await pumpIn(tester, const ImageViewer(id: 'a'));
      await tester.pump();

      expect(find.text('Change it'), findsNothing);
    });
  });

  testWidgets('a recorded picture offers Delete', (tester) async {
    // The control. Without it the assertion above passes just as well on a
    // viewer that never offers Delete to anyone.
    await tester.runAsync(() => images.save(
          MadeImage(
            id: 'a',
            prompt: 'a cat',
            provider: 'gemini',
            model: 'nano',
            mimeType: 'image/png',
            createdAt: DateTime(2026),
          ),
          _onePixelPng,
        ));

    await pumpIn(tester, const ImageViewer(id: 'a'));
    await tester.pump();

    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('a picture with no record still offers Save, not Copy prompt',
      (tester) async {
    // What a private chat produces: drawable, with nothing recorded about it.
    // Offering "Copy prompt" over an empty string would be a control that
    // silently does nothing.
    images.hold('p', _onePixelPng);

    await pumpIn(tester, const ImageViewer(id: 'p'));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Copy prompt'), findsNothing);
  });
}

/// A real 1×1 PNG. `Image.memory` decodes its input, so made-up bytes would
/// fail to draw and the assertion would be about the fixture.
final _onePixelPng = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
  0x42, 0x60, 0x82,
]);
