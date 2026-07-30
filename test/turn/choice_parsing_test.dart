import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/turn/choice_parsing.dart';

void main() {
  group('parseChoiceBlock', () {
    test('reads a well-formed block', () {
      final choice = parseChoiceBlock(
          '{"question": "Which tone?", "options": ["Warm", "Bold"]}');

      expect(choice, isNotNull);
      expect(choice!.question, 'Which tone?');
      expect(choice.options, ['Warm', 'Bold']);
      expect(choice.multiSelect, isFalse);
    });

    test('honours multiSelect', () {
      final choice = parseChoiceBlock('{"question": "Which platforms?", '
          '"options": ["TikTok", "LinkedIn"], "multiSelect": true}');

      expect(choice!.multiSelect, isTrue);
    });

    test('trims and drops blank options', () {
      final choice = parseChoiceBlock(
          '{"question": " Which tone? ", "options": ["  Warm ", "", "Bold"]}');

      expect(choice!.question, 'Which tone?');
      expect(choice.options, ['Warm', 'Bold']);
    });

    test('malformed JSON is not a choice', () {
      expect(parseChoiceBlock('not json at all'), isNull);
      expect(parseChoiceBlock('{"question": "Which tone?",'), isNull);
      expect(parseChoiceBlock('["Warm", "Bold"]'), isNull);
      expect(parseChoiceBlock(''), isNull);
    });

    test('a question with no options is worse than no question', () {
      expect(
        parseChoiceBlock('{"question": "Which tone?", "options": []}'),
        isNull,
      );
      expect(
        parseChoiceBlock('{"question": "Which tone?"}'),
        isNull,
      );
    });

    test('one option is an instruction, not a choice', () {
      expect(
        parseChoiceBlock('{"question": "Which tone?", "options": ["Warm"]}'),
        isNull,
      );
    });

    test('too many options is a list to read, not a decision', () {
      final options = List.generate(maxChoiceOptions + 1, (i) => 'Option $i');
      expect(
        parseChoiceBlock(
            '{"question": "Which?", "options": ${options.map((o) => '"$o"').toList()}}'),
        isNull,
      );
    });

    test('duplicate options are rejected — two chips that do the same thing '
        'is a broken question', () {
      expect(
        parseChoiceBlock(
            '{"question": "Which tone?", "options": ["Warm", "Warm"]}'),
        isNull,
      );
    });

    test('an empty question is rejected', () {
      expect(
        parseChoiceBlock('{"question": "  ", "options": ["Warm", "Bold"]}'),
        isNull,
      );
    });
  });

  group('findChoiceIn', () {
    test('finds a fenced block among prose', () {
      const reply = 'Happy to write that — what is it for?\n\n'
          '```$choiceFenceTag\n'
          '{"question": "Which platform?", "options": ["TikTok", "Email"]}\n'
          '```\n\n'
          'Tell me and I will draft it.';

      final choice = findChoiceIn(reply);
      expect(choice!.options, ['TikTok', 'Email']);
    });

    test('plain prose carries no choice', () {
      expect(findChoiceIn('Which tone would you like — warm or bold?'), isNull);
    });

    test('a fenced block that is not a choice is ignored', () {
      expect(findChoiceIn('```json\n{"question": "x"}\n```'), isNull);
    });
  });

  group('stripChoiceBlock', () {
    test('removes the block and leaves the prose', () {
      const reply = 'What is it for?\n\n'
          '```$choiceFenceTag\n'
          '{"question": "Which platform?", "options": ["TikTok", "Email"]}\n'
          '```';

      expect(stripChoiceBlock(reply), 'What is it for?');
    });

    test('text with no block is unchanged apart from trimming', () {
      expect(stripChoiceBlock('Just prose.'), 'Just prose.');
    });
  });
}
