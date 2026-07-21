import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/services/translate_service.dart';

void main() {
  group('parseTargetLanguage', () {
    test('reads a "to/into/in <language>" cue', () {
      expect(TranslateService.parseTargetLanguage('translate this to Spanish'),
          'Spanish');
      expect(TranslateService.parseTargetLanguage('render it into french'),
          'French');
      expect(TranslateService.parseTargetLanguage('say hello in Japanese'),
          'Japanese');
    });

    test('does not read a non-language word as a language', () {
      expect(TranslateService.parseTargetLanguage('translate this to me'),
          isNull);
    });

    test('finds a bare language mention', () {
      expect(TranslateService.parseTargetLanguage('German translation please'),
          'German');
    });
  });

  group('extractSourceText', () {
    test('takes everything after a colon verbatim', () {
      expect(
          TranslateService.extractSourceText('translate to French: Hello world'),
          'Hello world');
    });

    test('strips the command and the language clause', () {
      expect(
          TranslateService.extractSourceText(
              'please translate the following to Spanish good morning'),
          'good morning');
    });

    test('keeps the text when there is no command wrapper', () {
      expect(TranslateService.extractSourceText('Hello there in German'),
          'Hello there');
    });
  });

  group('prompts', () {
    test('translationPrompt names the target and includes the source', () {
      final p = TranslateService.translationPrompt('hi', 'French');
      expect(p, contains('into French'));
      expect(p, contains('hi'));
      expect(p.toLowerCase(), contains('only'));
    });

    test('simulatedTranslation is clearly labelled', () {
      final s = TranslateService.simulatedTranslation('hi', 'French');
      expect(s, contains('Simulated French'));
      expect(s, contains('API key'));
    });
  });
}
