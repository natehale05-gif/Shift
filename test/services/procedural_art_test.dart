import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/features/studios/media/procedural_art.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('paletteFromSeed', () {
    test('is deterministic for a given seed', () {
      expect(paletteFromSeed(42), paletteFromSeed(42));
    });

    test('always returns three colors from the shared palette', () {
      final colors = paletteFromSeed(7);
      expect(colors, hasLength(3));
      for (final color in colors) {
        expect(proceduralArtPalette, contains(color));
      }
    });
  });

  group('rasterizeGradientArt', () {
    test('produces a valid, non-empty PNG', () async {
      final bytes = await rasterizeGradientArt(seed: 123, size: 32);
      expect(bytes, isNotEmpty);
      // PNG magic bytes.
      expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('is deterministic for the same seed', () async {
      final a = await rasterizeGradientArt(seed: 5, size: 16);
      final b = await rasterizeGradientArt(seed: 5, size: 16);
      expect(a, b);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
