

/// Pure helpers for the Deck studio: pull the topic + slide count from a
/// request, build the outline prompt, parse the model's JSON outline, provide a
/// templated fallback, and render an HTML deck for the artifact panel.
library;
import '../../../data/models/studio_result.dart';
import 'dart:convert';

class DeckService {
  DeckService._();

  static const defaultSlideCount = 6;

  /// The words that name the deliverable rather than the subject. Anchored at
  /// the use site, since it has to be stripped from either end.
  static const _deckNoun = r'(slide\s*deck|pitch\s*deck|deck|presentation|'
      r'powerpoint|pptx|keynote|slides)';

  /// Extracts the deck topic and desired slide count from a free-form request.
  static ({String topic, int slideCount}) parseDeckRequest(String input) {
    final countMatch =
        RegExp(r'(\d+)\s*slides?', caseSensitive: false).firstMatch(input);
    final slideCount =
        (countMatch != null ? int.parse(countMatch.group(1)!) : defaultSlideCount)
            .clamp(3, 20);

    // Three passes, because the deck noun is not always where a single
    // pattern would expect it. "Build me a presentation about X" puts it right
    // after the article; "build me a small business presentation" puts it at
    // the very end, with the topic in between. One combined pattern matched
    // only the first, so the second kept the entire prompt as its topic and
    // the deck was titled "build me a small business presentation".
    var topic = input
        .replaceAll(RegExp(r'(\d+)\s*slides?', caseSensitive: false), '')
        // 1. the request preamble, whether or not a deck noun follows it
        .replaceFirst(
            RegExp(
                r'^\s*(please\s+)?(can|could|would)?\s*(you\s+)?(please\s+)?'
                r'(make|build|create|generate|draft|put together|design)\s+'
                // "an" before "a": alternation is first-match, so the shorter
                // one would eat the "a" of "an investor" and leave "n".
                r'(me|us)?\s*(an|a|the)?\b\s*',
                caseSensitive: false),
            '')
        // 2. the deck noun itself, at either end
        .replaceFirst(
            RegExp('^\\s*$_deckNoun\\s*', caseSensitive: false), '')
        .replaceFirst(
            RegExp('\\s*$_deckNoun\\s*\$', caseSensitive: false), '')
        // 3. a preposition left dangling by either removal
        .replaceFirst(RegExp(r'^\s*(about|on|for|covering|regarding)\s+',
            caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s+(about|on|for|covering|regarding)\s*\$',
            caseSensitive: false), '')
        .trim();
    if (topic.isEmpty) topic = 'Your Topic';
    return (topic: topic, slideCount: slideCount);
  }

  /// The instruction handed to the best available text provider — asks for a
  /// strict JSON outline so it parses deterministically.
  static String outlinePrompt(String topic, int slideCount) =>
      'Create a $slideCount-slide presentation outline about "$topic". '
      'Respond with ONLY a minified JSON array of exactly $slideCount objects, '
      'each {"title": string, "bullets": [3-4 short strings]}. The first slide '
      'is the title slide (its bullets are a one-line subtitle). No prose, no '
      'code fences.';

  /// Parses the model's JSON outline into a [DeckResult]. Returns null on
  /// anything unparseable so the caller can fall back to the template.
  static DeckResult? parseOutlineJson(String reply, String topic) {
    try {
      final cleaned =
          reply.replaceAll(RegExp(r'```(json)?'), '').trim();
      final decoded = jsonDecode(cleaned) as List<dynamic>;
      final slides = decoded
          .map((s) => DeckSlide.fromJson(s as Map<String, dynamic>))
          .where((s) => s.title.isNotEmpty)
          .toList();
      if (slides.isEmpty) return null;
      return DeckResult(title: slides.first.title, slides: slides, live: true);
    } catch (_) {
      return null;
    }
  }

  /// Deterministic fallback outline used when no live provider is available.
  static DeckResult templatedDeck(String topic, int slideCount) {
    final sections = [
      ('Overview', ['What $topic is', 'Why it matters now', 'Who it\'s for']),
      ('The Problem', ['The status quo', 'Where it breaks down', 'The cost of inaction']),
      ('Our Approach', ['The core idea', 'How it works', 'What makes it different']),
      ('How It Works', ['Step one', 'Step two', 'Step three']),
      ('Results', ['What improves', 'By how much', 'Proof points']),
      ('Roadmap', ['Now', 'Next', 'Later']),
      ('The Team', ['Who\'s building it', 'Track record', 'Advisors']),
      ('The Ask', ['What we need', 'What you get', 'Next steps']),
    ];
    final slides = <DeckSlide>[
      DeckSlide(title: topic, bullets: ['A SHIFT AI presentation']),
      for (var i = 0; i < slideCount - 1; i++)
        DeckSlide(
          title: sections[i % sections.length].$1,
          bullets: sections[i % sections.length].$2,
        ),
    ];
    return DeckResult(title: topic, slides: slides, live: false);
  }

  /// A simple self-contained HTML deck (one section per slide) for the
  /// artifact preview panel.
  static String buildDeckHtml(DeckResult deck) {
    String esc(String s) => s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
    final slidesHtml = deck.slides.map((s) {
      final bullets = s.bullets.isEmpty
          ? ''
          : '<ul>${s.bullets.map((b) => '<li>${esc(b)}</li>').join()}</ul>';
      return '<section class="slide"><h2>${esc(s.title)}</h2>$bullets</section>';
    }).join();
    return '''
<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>${esc(deck.title)}</title>
<style>
  body { margin:0; font-family: system-ui, sans-serif; background:#F5F4EF; color:#1d1d1f; }
  .slide { max-width:900px; margin:24px auto; padding:48px 56px; background:#fff;
           border-radius:16px; box-shadow:0 1px 3px rgba(0,0,0,.08); aspect-ratio:16/9;
           display:flex; flex-direction:column; justify-content:center; }
  h2 { font-family:Georgia, serif; font-size:34px; margin:0 0 20px; }
  ul { font-size:20px; line-height:1.7; color:#3a3a3c; padding-left:24px; }
  li { margin-bottom:8px; }
</style></head>
<body>$slidesHtml</body></html>
''';
  }
}
