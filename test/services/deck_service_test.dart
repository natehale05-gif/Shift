import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/services/deck_service.dart';

void main() {
  group('parseDeckRequest', () {
    test('extracts the topic and default slide count', () {
      final r = DeckService.parseDeckRequest('make me a deck about our roadmap');
      expect(r.topic, 'our roadmap');
      expect(r.slideCount, DeckService.defaultSlideCount);
    });

    test('reads an explicit slide count', () {
      final r =
          DeckService.parseDeckRequest('build a 10 slide presentation on climate');
      expect(r.topic, 'climate');
      expect(r.slideCount, 10);
    });

    test('clamps an absurd slide count', () {
      expect(DeckService.parseDeckRequest('a 99 slide deck on x').slideCount, 20);
    });

    test('falls back to a placeholder topic', () {
      expect(DeckService.parseDeckRequest('make a deck').topic, 'Your Topic');
    });
  });

  group('parseOutlineJson', () {
    test('parses a JSON outline into live slides', () {
      const reply =
          '[{"title":"Intro","bullets":["a","b"]},{"title":"End","bullets":["c"]}]';
      final deck = DeckService.parseOutlineJson(reply, 'x')!;
      expect(deck.live, isTrue);
      expect(deck.slides, hasLength(2));
      expect(deck.title, 'Intro');
      expect(deck.slides[0].bullets, ['a', 'b']);
    });

    test('tolerates a code fence', () {
      const reply = '```json\n[{"title":"Only","bullets":[]}]\n```';
      expect(DeckService.parseOutlineJson(reply, 'x')?.slides, hasLength(1));
    });

    test('returns null on garbage', () {
      expect(DeckService.parseOutlineJson('not json', 'x'), isNull);
    });
  });

  group('templatedDeck', () {
    test('produces the requested number of slides, title slide first', () {
      final deck = DeckService.templatedDeck('Widgets', 5);
      expect(deck.live, isFalse);
      expect(deck.slides, hasLength(5));
      expect(deck.slides.first.title, 'Widgets');
    });
  });

  group('buildDeckHtml', () {
    test('renders one section per slide and escapes HTML', () {
      final deck = DeckService.templatedDeck('A & B', 3);
      final html = DeckService.buildDeckHtml(deck);
      expect('<section class="slide">'.allMatches(html).length, 3);
      expect(html, contains('A &amp; B'));
    });
  });
}
