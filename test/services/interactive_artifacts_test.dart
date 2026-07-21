import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/services/interactive_artifacts.dart';

void main() {
  group('detect', () {
    test('recognises each interactive kind', () {
      expect(InteractiveArtifacts.detect('make a recipe card for lasagna'),
          InteractiveKind.recipe);
      expect(InteractiveArtifacts.detect('build a quiz about space'),
          InteractiveKind.quiz);
      expect(InteractiveArtifacts.detect('flashcards for spanish verbs'),
          InteractiveKind.flashcards);
      expect(InteractiveArtifacts.detect('a packing list for camping'),
          InteractiveKind.checklist);
    });

    test('leaves ordinary prompts alone', () {
      expect(InteractiveArtifacts.detect('build me a landing page'), isNull);
      expect(InteractiveArtifacts.detect('what time is it'), isNull);
    });
  });

  group('parseTopic', () {
    test('strips the command and kind words', () {
      expect(
          InteractiveArtifacts.parseTopic(
              'make an interactive recipe card for banana bread',
              InteractiveKind.recipe),
          'banana bread');
      expect(
          InteractiveArtifacts.parseTopic(
              'build a quiz about the solar system', InteractiveKind.quiz),
          'the solar system');
    });
  });

  group('renderers produce runnable, interactive HTML', () {
    test('recipe embeds ingredients, steps, a timer and a servings scaler', () {
      final html = InteractiveArtifacts.renderRecipe(
          InteractiveArtifacts.templatedRecipe('cookies'),
          heroImageDataUri: 'data:image/png;base64,AA==');
      expect(html, contains('<!DOCTYPE html>'));
      expect(html, contains('<script>'));
      expect(html, contains('class="ing"')); // checkable ingredients
      expect(html, contains('Start timer'));
      expect(html, contains('id="serv"'));
      expect(html, contains('data:image/png;base64,AA==')); // hero image
    });

    test('quiz embeds questions, options and scoring JS', () {
      final html = InteractiveArtifacts.renderQuiz(
          InteractiveArtifacts.templatedQuiz('space'), 'Space Quiz');
      expect(html, contains('data-answer='));
      expect(html, contains('Check answers'));
      expect(html, contains('You scored'));
    });

    test('flashcards embed the cards as JSON and a flip handler', () {
      final html = InteractiveArtifacts.renderFlashcards(
          InteractiveArtifacts.templatedFlashcards('verbs'), 'Verbs');
      expect(html, contains('const cards=['));
      expect(html, contains('flip'));
    });

    test('checklist embeds items, a progress bar and an add control', () {
      final html = InteractiveArtifacts.renderChecklist(
          InteractiveArtifacts.templatedChecklist('camping'), 'Camping');
      expect(html, contains('class="it"'));
      expect(html, contains('id="fill"'));
      expect(html, contains('Add an item'));
    });

    test('HTML-escapes content', () {
      final html = InteractiveArtifacts.renderChecklist(
          ['buy <bread> & milk'], 'Groceries & <b>');
      expect(html, contains('buy &lt;bread&gt; &amp; milk'));
      expect(html, isNot(contains('<bread>')));
    });
  });

  group('JSON parsing (live content)', () {
    test('parses a recipe object', () {
      const reply =
          '{"title":"Pesto","servings":2,"minutes":15,"ingredients":'
          '[{"qty":"1 cup","item":"basil"}],"steps":["blend it"]}';
      final r = InteractiveArtifacts.parseRecipeJson(reply, 'x')!;
      expect(r.title, 'Pesto');
      expect(r.servings, 2);
      expect(r.ingredients.single.item, 'basil');
      expect(r.steps.single, 'blend it');
    });

    test('parses a quiz array and clamps a bad answer index', () {
      const reply =
          '[{"question":"Q","options":["a","b"],"answerIndex":9}]';
      final qs = InteractiveArtifacts.parseQuizJson(reply)!;
      expect(qs.single.answerIndex, 1);
    });

    test('returns null on garbage', () {
      expect(InteractiveArtifacts.parseRecipeJson('nope', 'x'), isNull);
      expect(InteractiveArtifacts.parseQuizJson('nope'), isNull);
      expect(InteractiveArtifacts.parseFlashcardsJson('nope'), isNull);
      expect(InteractiveArtifacts.parseChecklistJson('nope'), isNull);
    });
  });
}
