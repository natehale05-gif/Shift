import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/asset_store.dart';
import 'package:shift/data/image_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/made_image.dart';
import 'package:shift/features/visual/image_viewer.dart';
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

  Future<void> pumpIn(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<ImageStore>.value(
        value: images,
        child: MaterialApp(
          theme: shiftTheme(Brightness.light, TargetPlatform.linux),
          home: Scaffold(body: child),
        ),
      ),
    );
  }

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
