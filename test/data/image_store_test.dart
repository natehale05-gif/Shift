import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/data/asset_store.dart';
import 'package:shift/data/image_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/made_image.dart';

/// Pictures, against a real directory and a real file.
///
/// The whole design is a split — records in the key-value map, bytes on disk —
/// so a double that keeps both in one map would be testing something else. The
/// interesting failures are all at the seam between the two halves.
void main() {
  late Directory dir;
  late KvStore kv;
  late AssetStore assets;
  late ImageStore images;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-images');
    kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    assets = AssetStore(directory: '${dir.path}/assets');
    images = ImageStore(kv, assets);
    await images.load();
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  MadeImage record(String id, {String prompt = 'a cat'}) => MadeImage(
        id: id,
        prompt: prompt,
        provider: 'gemini',
        model: 'nano-banana',
        mimeType: 'image/png',
        createdAt: DateTime(2026, 1, 1),
      );

  Uint8List bytes(int seed) =>
      Uint8List.fromList([137, 80, 78, 71, seed, seed, seed]);

  test('a picture survives a reload, bytes and all', () async {
    await images.save(record('a'), bytes(1));

    final reopened = ImageStore(
      KvStore(path: '${dir.path}/kv.json'),
      AssetStore(directory: '${dir.path}/assets'),
    );
    await reopened.load();

    expect(reopened.index.single.id, 'a');
    expect(reopened.index.single.prompt, 'a cat');
    expect(await reopened.bytes('a'), bytes(1));
  });

  test('the bytes are not in the key-value file', () async {
    // The reason the two halves exist. Base64 in the map would be rewritten to
    // disk by every unrelated save, and on the web would exhaust localStorage
    // after about three pictures.
    await images.save(record('a'), bytes(1));

    final raw = await File('${dir.path}/kv.json').readAsString();
    expect(raw, contains('a cat'), reason: 'the record is there');
    expect(raw.length, lessThan(2000),
        reason: 'the index is small because the bytes are elsewhere');
    expect(File('${dir.path}/assets/a').existsSync(), isTrue);
  });

  test('newest first', () async {
    await images.save(record('a', prompt: 'first'), bytes(1));
    await images.save(record('b', prompt: 'second'), bytes(2));

    expect([for (final i in images.index) i.prompt], ['second', 'first']);
  });

  test('removing one takes its bytes with it', () async {
    await images.save(record('a'), bytes(1));
    await images.save(record('b'), bytes(2));

    await images.remove('a');

    expect(images.index.single.id, 'b');
    expect(await assets.get('a'), isNull);
    expect(await assets.get('b'), isNotNull, reason: 'only that one');
  });

  test('an index entry with no bytes reads as missing, not as a crash',
      () async {
    // The recoverable direction of a disagreement between the two halves: the
    // tile shows as broken and can be deleted.
    await images.save(record('a'), bytes(1));
    await assets.remove('a');

    final reopened = ImageStore(
      KvStore(path: '${dir.path}/kv.json'),
      AssetStore(directory: '${dir.path}/assets'),
    );
    await reopened.load();

    expect(reopened.record('a'), isNotNull);
    expect(await reopened.bytes('a'), isNull);
  });

  test('bytes with no index entry are swept', () async {
    // The unrecoverable direction: nothing can show them and nothing can
    // delete them, so left alone they only accumulate.
    await images.save(record('a'), bytes(1));
    await assets.put('orphan', bytes(9));

    expect(await images.sweep(), 1);

    expect(await assets.get('orphan'), isNull);
    expect(await assets.get('a'), isNotNull, reason: 'the kept one stays');
  });

  test('a sweep with nothing to sweep removes nothing', () async {
    // The control. Without it "swept" and "found nothing" are the same result
    // and the assertion above proves neither.
    await images.save(record('a'), bytes(1));
    expect(await images.sweep(), 0);
    expect(await assets.get('a'), isNotNull);
  });

  test('held bytes are readable but never written', () async {
    // What a private chat needs: the picture is on screen for the session and
    // there is nothing on disk afterwards.
    images.hold('p', bytes(7));

    expect(images.cached('p'), bytes(7));
    expect(images.index, isEmpty);
    expect(await assets.get('p'), isNull);
    expect(File('${dir.path}/kv.json').existsSync(), isFalse);
  });

  test('the cache never evicts a held picture', () async {
    // A held one has nowhere to be read back from, so evicting it would blank
    // an image still on screen with no way to recover it.
    images.hold('p', bytes(7));
    for (var i = 0; i < 40; i++) {
      await images.save(record('k$i'), bytes(i));
    }
    expect(images.cached('p'), bytes(7));
  });

  test('the download name keeps the subject, not the request', () async {
    // The regression v1 fixed in A4 and this rediscovered in a real save
    // dialog: cutting the raw prompt at six words names the asking and drops
    // the thing being asked for.
    final image = record('a', prompt: 'make me a picture of a sunset over water');

    expect(image.filename, isNot(contains('make')));
    expect(image.filename, contains('sunset'));
    expect(image.filename, endsWith('.png'));
  });

  test('a prompt that is only preamble still gets a name', () async {
    expect(record('a', prompt: 'please make me one').filename,
        endsWith('.png'));
    expect(record('a', prompt: '   ').filename, 'image.png');
  });

  test('an id that would escape the directory is refused', () async {
    await assets.put('../escaped', bytes(1));

    expect(await assets.get('../escaped'), isNull);
    expect(File('${dir.path}/escaped').existsSync(), isFalse);
  });
}
