import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/features/chat/walking_animal.dart';

void main() {
  group('animalForSeed', () {
    test('the three animals are all reachable', () {
      final seen = {for (var s = 0; s < 30; s++) animalForSeed(s)};

      expect(seen, {
        WalkingAnimal.deer,
        WalkingAnimal.rabbit,
        WalkingAnimal.fox,
      });
    });

    test('never repeats the one shown last', () {
      // With three animals, plain random comes up the same about a third of
      // the time, which reads as the app being stuck rather than as chance.
      for (final last in WalkingAnimal.values) {
        for (var s = 0; s < 30; s++) {
          expect(animalForSeed(s, avoid: last), isNot(last));
        }
      }
    });

    test('avoiding one still reaches both others', () {
      final seen = {
        for (var s = 0; s < 30; s++)
          animalForSeed(s, avoid: WalkingAnimal.fox)
      };

      expect(seen, {WalkingAnimal.deer, WalkingAnimal.rabbit});
    });

    test('a negative seed is handled', () {
      // The seed is a clock value elsewhere, but nothing stops it going
      // negative, and `% length` on a negative int is negative in Dart —
      // which would be a range error rather than a wrong animal.
      expect(() => animalForSeed(-7), returnsNormally);
    });

    test('the same seed gives the same animal', () {
      expect(animalForSeed(12345), animalForSeed(12345));
    });
  });

  testWidgets('the strip paints and keeps animating', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WalkingAnimalStrip(
          animal: WalkingAnimal.deer,
          color: Color(0xFFAF52DE),
        ),
      ),
    ));

    expect(find.byType(WalkingAnimalStrip), findsOneWidget);
    // A repeating controller never settles, so pumpAndSettle would hang —
    // stepping it proves the animation is running rather than stuck.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every animal paints without throwing', (tester) async {
    for (final animal in WalkingAnimal.values) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WalkingAnimalStrip(animal: animal, color: const Color(0xFF000000)),
        ),
      ));
      // Several points around the loop, so the turn-around and both gait
      // extremes are all painted at least once.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 700));
      }
      expect(tester.takeException(), isNull, reason: animal.name);
    }
  });
}
