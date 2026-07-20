import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/models/studio_type.dart';
import 'package:shift_ai/services/studio_response_bank.dart';

void main() {
  group('clarifyingQuestion', () {
    test('asks for terse studio prompts', () {
      expect(
        StudioResponseBank.clarifyingQuestion(
            StudioType.imageStudio, 'make me a logo'),
        isNotNull,
      );
      expect(
        StudioResponseBank.clarifyingQuestion(
            StudioType.musicStudio, 'write a song'),
        isNotNull,
      );
      expect(
        StudioResponseBank.clarifyingQuestion(
            StudioType.codeStudio, 'write some code'),
        isNotNull,
      );
    });

    test('every question ends with a question mark', () {
      for (final studio in StudioType.values) {
        if (studio == StudioType.middleware) continue;
        final question = StudioResponseBank.clarifyingQuestion(studio, 'x');
        expect(question, isNotNull, reason: studio.name);
        expect(question!.trimRight(), endsWith('?'), reason: studio.name);
      }
    });

    test('stays null for descriptive prompts', () {
      expect(
        StudioResponseBank.clarifyingQuestion(
          StudioType.imageStudio,
          'a minimalist navy blue logo for my coffee shop called Northbound',
        ),
        isNull,
      );
      expect(
        StudioResponseBank.clarifyingQuestion(
          StudioType.codeStudio,
          'write a python function that reverses a string',
        ),
        isNull,
      );
    });

    test('middleware never asks (it is not a studio deliverable)', () {
      expect(
        StudioResponseBank.clarifyingQuestion(StudioType.middleware, 'hi'),
        isNull,
      );
    });
  });

  group('clarificationAck', () {
    test('non-middleware studios have a non-empty acknowledgment', () {
      for (final studio in StudioType.values) {
        if (studio == StudioType.middleware) continue;
        expect(StudioResponseBank.clarificationAck(studio), isNotEmpty,
            reason: studio.name);
      }
    });

    test('middleware has no acknowledgment (never used)', () {
      expect(StudioResponseBank.clarificationAck(StudioType.middleware), '');
    });
  });
}
