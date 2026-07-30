import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/features/chat/greeting.dart';

DateTime at(int hour) => DateTime(2026, 7, 30, hour);

void main() {
  _bandTimeWords();
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

    test('every band offers plenty to rotate through', () {
      // Four variants meant a repeat every few chats even with a good seed.
      for (final hour in [9, 14, 19, 2]) {
        final seen = {
          for (var seed = 0; seed < 60; seed++)
            greetingFor(now: at(hour), seed: seed)
        };
        expect(seen.length, greaterThanOrEqualTo(10), reason: 'hour $hour');
      }
    });
  });

  group('never the same as last time', () {
    test('the avoided line is not returned', () {
      for (final hour in [9, 14, 19, 2]) {
        final previous = greetingFor(now: at(hour), seed: 3);
        for (var seed = 0; seed < 60; seed++) {
          expect(greetingFor(now: at(hour), seed: seed, avoid: previous),
              isNot(previous),
              reason: 'hour $hour, seed $seed');
        }
      }
    });

    test('avoiding still works once a name is set', () {
      // The stored value is the bare line, so a nickname appearing (or
      // changing) between chats must not defeat the comparison.
      const previous = 'Good evening';
      for (var seed = 0; seed < 40; seed++) {
        final greeting =
            greetingFor(now: at(19), seed: seed, name: 'Nate', avoid: previous);
        expect(greeting, isNot(startsWith(previous)), reason: 'seed $seed');
      }
    });

    test('the stored line is the variant itself, commas and all', () {
      // Splitting the rendered greeting on its last comma would truncate a
      // line that contains one — and a truncated value never matches, which
      // silently turns the avoidance off for exactly that line.
      for (var seed = 0; seed < 40; seed++) {
        final line = greetingLineFor(now: at(19), seed: seed);
        expect(greetingFor(now: at(19), seed: seed, name: 'Nate'),
            '$line, Nate',
            reason: 'seed $seed');
      }
    });

    test('an unknown or empty avoid value changes nothing', () {
      for (final avoid in [null, '', 'Something never used']) {
        expect(greetingFor(now: at(19), seed: 0, avoid: avoid), isNotEmpty);
      }
    });
  });
}

void _bandTimeWords() {
  // Words that name a time of day, and which band each is allowed in. The
  // small-hours set used to carry "Good evening", so a chat opened at 2am was
  // greeted as if it were 7pm — this asserts the rule rather than that one
  // line, so the next slip is caught too.
  const bands = <String, (List<String>, List<String>)>{
    'morning': (morningVariants, ['morning']),
    'afternoon': (afternoonVariants, ['afternoon', 'mid-day', 'midday']),
    'evening': (eveningVariants, ['evening', 'tonight', 'night']),
    'late': (lateVariants, ['tonight', 'night', 'late', 'midnight', 'hour']),
  };
  const timeWords = [
    'morning', 'afternoon', 'evening', 'tonight', 'midnight', 'midday',
    'mid-day',
  ];

  group('time-of-day lines only appear in their own band', () {
    bands.forEach((name, entry) {
      final (variants, allowed) = entry;
      test('the $name band', () {
        for (final line in variants) {
          final lower = line.toLowerCase();
          for (final word in timeWords) {
            if (!lower.contains(word)) continue;
            expect(allowed.contains(word), isTrue,
                reason: '"$line" names "$word" but sits in the $name band');
          }
        }
      });
    });
  });

  test('every band offers a decent spread', () {
    for (final variants in [
      morningVariants,
      afternoonVariants,
      eveningVariants,
      lateVariants,
    ]) {
      expect(variants.length, greaterThanOrEqualTo(20));
      expect(variants.toSet().length, variants.length,
          reason: 'a duplicate makes the rotation feel stuck');
    }
  });
}
