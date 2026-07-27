import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/studio_result.dart';
import 'package:shift_ai/services/brand_pack_service.dart';

BrandPackResult _pack(String name) {
  final seed = BrandPackService.seedFor(name);
  final fonts = BrandPackService.fontPair(seed);
  return BrandPackResult(
    brandName: name,
    palette: BrandPackService.buildPalette(seed),
    headingFont: fonts.heading,
    bodyFont: fonts.body,
    seed: seed,
  );
}

void main() {
  group('parseBrandName', () {
    test('strips the command wrapper', () {
      expect(BrandPackService.parseBrandName('make me a brand pack for Northbound'),
          'Northbound');
      expect(BrandPackService.parseBrandName('build a brand kit called Acme Co'),
          'Acme Co');
    });

    test('falls back to a placeholder', () {
      expect(BrandPackService.parseBrandName('make a brand pack'), 'Your Brand');
    });
  });

  group('palette', () {
    test('is five valid hex colours and deterministic', () {
      final a = BrandPackService.buildPalette(BrandPackService.seedFor('X'));
      final b = BrandPackService.buildPalette(BrandPackService.seedFor('X'));
      expect(a, b);
      expect(a, hasLength(5));
      for (final c in a) {
        expect(RegExp(r'^#[0-9A-F]{6}$').hasMatch(c), isTrue, reason: c);
      }
    });
  });

  group('buildZip', () {
    final logo = Uint8List.fromList(List.filled(20, 42));

    test('produces a decodable ZIP with logo + tokens + guidelines', () {
      final pack = _pack('Northbound Coffee');
      final bytes = BrandPackService.buildZip(pack, logo);
      final archive = ZipDecoder().decodeBytes(bytes);
      final names = archive.files.map((f) => f.name).toList();
      expect(names.any((n) => n.endsWith('/logo.png')), isTrue);
      expect(names.any((n) => n.endsWith('/colors.css')), isTrue);
      expect(names.any((n) => n.endsWith('/guidelines.md')), isTrue);
      expect(names.any((n) => n.endsWith('/palette.json')), isTrue);

      final logoFile =
          archive.files.firstWhere((f) => f.name.endsWith('/logo.png'));
      expect(logoFile.content, logo);
    });

    test('guidelines and css embed the brand name and palette', () {
      final pack = _pack('Acme');
      final archive =
          ZipDecoder().decodeBytes(BrandPackService.buildZip(pack, logo));
      final md = utf8.decode(archive.files
          .firstWhere((f) => f.name.endsWith('/guidelines.md'))
          .content as List<int>);
      final css = utf8.decode(archive.files
          .firstWhere((f) => f.name.endsWith('/colors.css'))
          .content as List<int>);
      expect(md, contains('Acme'));
      expect(md, contains(pack.palette.first));
      expect(css, contains('--brand-primary'));
      expect(css, contains(pack.palette.first));
    });
  });
}
