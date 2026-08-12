import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/core/platform/pick_image.dart';
import 'package:shift/data/asset_store.dart';
import 'package:shift/data/image_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/made_image.dart';

/// A picture the person brought, rather than one the app made.
void main() {
  group('what to tell the provider it is', () {
    test('the extension decides, because it is on every platform', () {
      // The picker reports a MIME type on some platforms and not others, and
      // a wrong one is a valid picture rejected for a reason nobody can see.
      expect(mimeTypeFor('holiday.JPG'), 'image/jpeg');
      expect(mimeTypeFor('logo.png'), 'image/png');
      expect(mimeTypeFor('shot.webp'), 'image/webp');
    });

    test('an unknown extension falls back to what the picker said', () {
      expect(mimeTypeFor('scan', 'image/tiff'), 'image/tiff');
      expect(mimeTypeFor('scan'), 'image/png');
    });

    test('the extension beats a disagreeing picker', () {
      // It comes from the file; the other comes from a plugin's guess.
      expect(mimeTypeFor('holiday.jpg', 'application/octet-stream'),
          'image/jpeg');
    });
  });

  group('a stored attached picture', () {
    late Directory dir;
    late ImageStore images;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('shift-attached');
      final kv = KvStore(path: '${dir.path}/kv.json');
      await kv.load();
      images = ImageStore(kv, AssetStore(directory: '${dir.path}/assets'));
      await images.load();
    });
    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    MadeImage attached(String id, String name) => MadeImage(
          id: id,
          prompt: name,
          provider: '',
          model: '',
          mimeType: mimeTypeFor(name),
          createdAt: DateTime(2026),
          origin: ImageOrigin.attached,
        );

    test('keeps the name it already had', () async {
      // Running a filename through the request-title rule would turn
      // `holiday-2019.jpg` into something the app invented.
      expect(attached('a', 'holiday-2019.jpg').filename, 'holiday-2019.jpg');
    });

    test('a made picture is still named from its request', () async {
      // The control: without it the rule above could be "never derive a name"
      // and this would still pass.
      final made = MadeImage(
        id: 'b',
        prompt: 'make me a picture of a sunset over water',
        provider: 'gemini',
        model: 'nano',
        mimeType: 'image/png',
        createdAt: DateTime(2026),
      );
      expect(made.filename, isNot(contains('make')));
    });

    test('its origin survives a reload', () async {
      await images.save(attached('a', 'holiday.jpg'),
          Uint8List.fromList([1, 2, 3]));

      final reopened = ImageStore(
        KvStore(path: '${dir.path}/kv.json'),
        AssetStore(directory: '${dir.path}/assets'),
      );
      await reopened.load();

      expect(reopened.record('a')?.origin, ImageOrigin.attached);
    });

    test('a picture stored by an earlier build reads as made', () async {
      // No `origin` on disk is the shape every picture had before this, and
      // it has to keep meaning what it meant.
      expect(
        MadeImage.fromJson({
          'id': 'a',
          'prompt': 'a cat',
          'createdAt': DateTime(2026).toIso8601String(),
        })?.origin,
        ImageOrigin.made,
      );
    });

    test('the source carries the type the picture actually is', () async {
      // Telling a provider a JPEG is a PNG gets it rejected.
      await images.save(attached('a', 'holiday.jpg'),
          Uint8List.fromList([1, 2, 3]));

      final source = await images.sourceFor('a');
      expect(source?.mimeType, 'image/jpeg');
      expect(source?.bytes, [1, 2, 3]);
    });

    test('nothing behind the id is no source at all', () async {
      expect(await images.sourceFor('missing'), isNull);
    });
  });
}
