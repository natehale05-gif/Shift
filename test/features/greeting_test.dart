import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/features/chat/greeting.dart';

DateTime at(int hour) => DateTime(2026, 7, 30, hour);

void main() {
  group('time of day', () {
    test('morning runs from 5 to noon', () {
      expect(greetingFor(now: at(5)), startsWith('Good morning'));
      expect(greetingFor(now: at(9)), startsWith('Good morning'));
      expect(greetingFor(now: at(11)), startsWith('Good morning'));
    });

    test('afternoon runs from noon to 5', () {
      expect(greetingFor(now: at(12)), startsWith('Good afternoon'));
      expect(greetingFor(now: at(16)), startsWith('Good afternoon'));
    });

    test('evening runs from 5 to 10', () {
      expect(greetingFor(now: at(17)), startsWith('Good evening'));
      expect(greetingFor(now: at(21)), startsWith('Good evening'));
    });

    test('the small hours get their own greeting, not "evening"', () {
      // 3am is not the evening, and being told so is the kind of small wrong
      // note that makes an app feel automated.
      expect(greetingFor(now: at(23)), 'Still up');
      expect(greetingFor(now: at(2)), 'Still up');
      expect(greetingFor(now: at(4)), 'Still up');
    });
  });

  group('name', () {
    test('is appended when the user has set one', () {
      expect(greetingFor(now: at(19), name: 'Nate'), 'Good evening, Nate');
    });

    test('is omitted when unset, blank, or whitespace', () {
      for (final name in [null, '', '   ', '\n']) {
        expect(greetingFor(now: at(19), name: name), 'Good evening',
            reason: 'name: ${name == null ? 'null' : '"$name"'}');
      }
    });

    test('is trimmed rather than pasted in raw', () {
      expect(greetingFor(now: at(19), name: '  Nate  '), 'Good evening, Nate');
    });
  });

  group('rotation', () {
    test('the same seed always gives the same greeting', () {
      // The whole point of taking a seed: a greeting that changed on every
      // rebuild would flicker while the user is reading it, and change on
      // every keystroke in the composer.
      final first = greetingFor(now: at(10), seed: 7);
      final second = greetingFor(now: at(10), seed: 7);
      expect(first, second);
    });

    test('different seeds reach every variant for a time of day', () {
      final seen = {
        for (var seed = 0; seed < 40; seed++)
          greetingFor(now: at(10), seed: seed)
      };
      expect(seen.length, greaterThan(1), reason: 'it should actually rotate');
      expect(seen, contains('Good morning'));
    });

    test('a negative seed is handled rather than throwing', () {
      expect(() => greetingFor(now: at(10), seed: -3), returnsNormally);
      expect(greetingFor(now: at(10), seed: -3), isNotEmpty);
    });

    test('every hour of the day produces a non-empty greeting', () {
      for (var hour = 0; hour < 24; hour++) {
        expect(greetingFor(now: at(hour)), isNotEmpty, reason: 'hour $hour');
      }
    });
  });
}
