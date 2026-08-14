import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/asset_store.dart';
import 'package:shift/data/image_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/made_image.dart';
import 'package:shift/features/visual/visual_surface.dart';
import 'package:shift/features/visual/visual_turns.dart';

/// Visual mode's surface.
void main() {
  late Directory dir;
  late ImageStore images;
  late VisualTurns turns;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-visual');
    final kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    final keys = ApiKeysStore(kv);
    await keys.load();
    images = ImageStore(kv, AssetStore(directory: '${dir.path}/assets'));
    await images.load();
    turns = VisualTurns(keys: keys, images: images);
  });
  tearDown(() async {
    turns.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<ImageStore>.value(value: images),
        ChangeNotifierProvider<VisualTurns>.value(value: turns),
      ],
      child: MaterialApp(
        theme: shiftTheme(Brightness.light, TargetPlatform.linux),
        home: const Scaffold(body: VisualSurface()),
      ),
    ));
    await tester.pump();
  }

  Future<void> seed(String id, String prompt) => images.save(
        MadeImage(
          id: id,
          prompt: prompt,
          provider: 'gemini',
          model: 'nano',
          mimeType: 'image/png',
          createdAt: DateTime(2026),
        ),
        _onePixelPng,
      );

  testWidgets('an empty gallery says what the mode is for', (tester) async {
    await pump(tester);

    expect(find.textContaining('Describe something'), findsOneWidget);
    expect(find.byType(GridView), findsNothing);
  });

  testWidgets('every picture is a tile, and each carries its prompt',
      (tester) async {
    // The prompt on the tile is what makes a grid searchable by eye. Without
    // it every picture is "an image" and finding one means opening all of
    // them.
    await tester.runAsync(() async {
      await seed('a', 'a vase of tulips');
      await seed('b', 'a lighthouse at dusk');
    });

    await pump(tester);
    await tester.pump();

    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('a vase of tulips'), findsOneWidget);
    expect(find.text('a lighthouse at dusk'), findsOneWidget);
  });

  testWidgets('newest first', (tester) async {
    await tester.runAsync(() async {
      await seed('a', 'first');
      await seed('b', 'second');
    });
    await pump(tester);
    await tester.pump();

    expect(tester.getTopLeft(find.text('second')).dx,
        lessThan(tester.getTopLeft(find.text('first')).dx));
  });

  testWidgets('a failure is shown here, not left in a hidden transcript',
      (tester) async {
    // There is no key, so the turn fails at once. The sentence lives on a
    // reply this surface never renders, and without the card a picture that
    // never arrives looks like a button that did nothing.
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'a vase of tulips');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();

    expect(find.textContaining('Settings'), findsOneWidget);
  });

  testWidgets('what it makes is not filed in whatever chat is open',
      (tester) async {
    // Visual shows no transcript, so appending to the open conversation would
    // put pictures into a chat about something else, invisibly.
    expect(turns.conversations, isNull);
  });
}

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
