import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/features/studios/deck/deck_service.dart';

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

  group('the deck noun can sit at the end of the request', () {
    test('"build me a small business presentation" is about small business',
        () {
      // The noun used to have to follow the verb, so this kept the whole
      // prompt as its topic and the deck was titled after the request.
      expect(DeckService.parseDeckRequest('build me a small business presentation')
          .topic,
          'small business');
    });

    test('other trailing-noun phrasings', () {
      String topic(String input) => DeckService.parseDeckRequest(input).topic;
      expect(topic('make a quarterly results deck'), 'quarterly results');
      expect(topic('create an investor pitch deck'), 'investor');
      expect(topic('design a product launch presentation'), 'product launch');
    });

    test('the leading-noun phrasings still work', () {
      String topic(String input) => DeckService.parseDeckRequest(input).topic;
      expect(topic('build me a presentation about solar power'), 'solar power');
      expect(topic('make a 5 slide deck on beekeeping'), 'beekeeping');
    });

    test('a request that is only the noun falls back rather than emptying', () {
      expect(DeckService.parseDeckRequest('make me a presentation').topic,
          'Your Topic');
    });
  });
}
