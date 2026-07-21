import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/services/short_reels_service.dart';

void main() {
  group('parseReelsRequest', () {
    test('reads count and topic', () {
      final r = ShortReelsService.parseReelsRequest('make 4 reels about cold brew');
      expect(r.count, 4);
      expect(r.topic, 'cold brew');
    });

    test('defaults the count', () {
      expect(
          ShortReelsService.parseReelsRequest('a short-form pack for my gym').count,
          ShortReelsService.defaultCount);
    });

    test('clamps the count', () {
      expect(ShortReelsService.parseReelsRequest('30 shorts about x').count, 8);
    });
  });

  group('parsePackJson', () {
    test('parses hooks + scripts as live reels with distinct seeds', () {
      const reply =
          '[{"hook":"Stop scrolling","script":"line1"},{"hook":"Try this","script":"line2"}]';
      final pack = ShortReelsService.parsePackJson(reply, 'topic')!;
      expect(pack.live, isTrue);
      expect(pack.reels, hasLength(2));
      expect(pack.reels[0].hook, 'Stop scrolling');
      expect(pack.reels[0].seed, isNot(pack.reels[1].seed));
    });

    test('returns null on garbage', () {
      expect(ShortReelsService.parsePackJson('nope', 't'), isNull);
    });
  });

  group('templatedPack', () {
    test('produces the requested number of reels with the topic woven in', () {
      final pack = ShortReelsService.templatedPack('cold brew', 3);
      expect(pack.live, isFalse);
      expect(pack.reels, hasLength(3));
      expect(pack.reels.any((r) => r.hook.contains('cold brew')), isTrue);
    });
  });

  group('buildZip', () {
    test('bundles one poster per reel + scripts.md + storyboard.html', () {
      final pack = ShortReelsService.templatedPack('cold brew', 3);
      final posters = [
        Uint8List.fromList([1]),
        Uint8List.fromList([2]),
        Uint8List.fromList([3]),
      ];
      final archive = ZipDecoder().decodeBytes(ShortReelsService.buildZip(pack, posters));
      final names = archive.files.map((f) => f.name).toList();
      expect(names.where((n) => n.endsWith('_poster.png')), hasLength(3));
      expect(names.any((n) => n.endsWith('/scripts.md')), isTrue);
      expect(names.any((n) => n.endsWith('/storyboard.html')), isTrue);

      final md = utf8.decode(archive.files
          .firstWhere((f) => f.name.endsWith('/scripts.md'))
          .content as List<int>);
      expect(md, contains('cold brew'));
      expect(md, contains(pack.reels.first.hook));
    });
  });
}
