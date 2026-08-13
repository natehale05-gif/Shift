import 'package:flutter_test/flutter_test.dart';
import 'package:shift/features/chat/citation_markers.dart';
import 'package:shift/turn/turn_event.dart';

Citation _at(String host, {int? start, int? end}) => Citation(
      title: host,
      url: Uri.parse('https://$host/page'),
      start: start,
      end: end,
    );

void main() {
  group('splicing markers', () {
    test('a marker lands where the provider said, not at the end', () {
      const text = 'It rained. It stopped.';
      final out = withCitationMarkers(text, [_at('a.test', start: 0, end: 10)]);

      expect(out, 'It rained.[¹](https://a.test/page) It stopped.');
    });

    test('two markers both land right, which needs descending order', () {
      // Front-to-back, the first insertion shifts the second offset by the
      // whole length of a URL and the second marker lands mid-word.
      const text = 'First fact. Second fact.';
      final out = withCitationMarkers(text, [
        _at('a.test', start: 0, end: 11),
        _at('b.test', start: 12, end: 24),
      ]);

      expect(out, 'First fact.[¹](https://a.test/page) '
          'Second fact.[²](https://b.test/page)');
    });

    test('a source with no offsets produces no marker', () {
      // Gemini's grounding gives sources without positions. They belong in the
      // rail, not guessed into a sentence.
      const text = 'Something true.';
      expect(withCitationMarkers(text, [_at('a.test')]), text);
    });

    test('an offset past the end is dropped, not clamped', () {
      // A provider disagreeing with itself about what it sent. Clamping would
      // put the marker on a sentence it may have nothing to do with.
      const text = 'Short.';
      expect(withCitationMarkers(text, [_at('a.test', start: 0, end: 900)]),
          text);
    });

    test('no citations changes nothing at all', () {
      expect(withCitationMarkers('untouched', const []), 'untouched');
    });
  });

  group('the rail', () {
    test('numbers agree with the markers', () {
      // The failure this prevents: a marker reading superscript-2 beside a rail
      // whose second row is a different page.
      final citations = [
        _at('a.test', start: 0, end: 3),
        _at('b.test', start: 4, end: 7),
      ];
      final rail = railOrder(citations);

      expect(rail.map((c) => c.title), ['a.test', 'b.test']);
      expect(withCitationMarkers('one two', citations),
          contains('[²](https://b.test/page)'));
    });

    test('the same page cited twice appears once', () {
      final rail = railOrder([
        _at('a.test', start: 0, end: 3),
        _at('a.test', start: 4, end: 7),
      ]);
      expect(rail, hasLength(1));
    });

    test('anyInline is false when nothing carries a position', () {
      expect(anyInline([_at('a.test')]), isFalse);
      expect(anyInline([_at('a.test', start: 0, end: 1)]), isTrue);
    });
  });
}
