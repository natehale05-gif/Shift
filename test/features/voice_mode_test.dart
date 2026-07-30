import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/features/chat/message/assistant_prose.dart';
import 'package:shift_ai/features/chat/message/building_indicator.dart';
import 'package:shift_ai/features/voice/voice_mode_controller.dart';

void main() {
  _priming();
  group('speakableText', () {
    test('a code block becomes a note, not a recital', () {
      // Read verbatim, a fenced block spells out every brace and semicolon —
      // a minute of noise for something the user can already see.
      const reply = 'Here you go:\n\n```html\n<h1>Hi</h1>\n```\n\nSave it.';
      final spoken = speakableText(reply);

      expect(spoken, isNot(contains('<h1>')));
      expect(spoken, contains('the code is on screen'),
          reason: 'saying nothing about it would be its own kind of lie');
      expect(spoken, contains('Here you go'));
      expect(spoken, contains('Save it'));
    });

    test('a reply cut off mid-block is still handled', () {
      final spoken = speakableText('Here:\n```html\n<html>');
      expect(spoken, isNot(contains('<html>')));
      expect(spoken, contains('the code is on screen'));
    });

    test('markdown punctuation is not announced', () {
      final spoken = speakableText(
          '## Heading\n\n- **bold** item\n- a `token` here\n\n> quoted');
      for (final marker in ['#', '*', '`', '>', '- ']) {
        expect(spoken, isNot(contains(marker)), reason: marker);
      }
      expect(spoken, contains('bold item'));
      expect(spoken, contains('token'));
    });

    test('links are read as their text, images dropped', () {
      final spoken =
          speakableText('See [the docs](https://example.com/a/b) and ![alt](x.png)');
      expect(spoken, contains('the docs'));
      expect(spoken, isNot(contains('example.com')));
      expect(spoken, isNot(contains('alt')));
    });

    test('plain prose passes through unchanged', () {
      expect(speakableText('The capital of France is Paris.'),
          'The capital of France is Paris.');
    });

    test('a reply that is only code produces nothing worth saying', () {
      // The caller checks for empty and goes back to listening rather than
      // speaking a bare parenthetical into the room.
      final spoken = speakableText('```dart\nvoid main() {}\n```');
      expect(spoken, '(the code is on screen)');
    });
  });

  group('buildingLabel', () {
    test('the making studios each say what they are making', () {
      expect(buildingLabel(StudioType.codeStudio), 'Building');
      expect(buildingLabel(StudioType.imageStudio), 'Drawing');
      expect(buildingLabel(StudioType.videoStudio), 'Filming');
      expect(buildingLabel(StudioType.musicStudio), 'Scoring');
      expect(buildingLabel(StudioType.deckStudio), 'Building the deck');
      expect(buildingLabel(StudioType.brandPackStudio), 'Designing');
      expect(buildingLabel(StudioType.shortReelsStudio), 'Cutting');
    });

    test('answering and translating stay "thinking"', () {
      // The hammer would be a lie over a turn that is only writing prose.
      expect(buildingLabel(StudioType.middleware), isNull);
      expect(buildingLabel(StudioType.translateStudio), isNull);
      expect(buildingLabel(StudioType.copyScriptsStudio), isNull);
      expect(buildingLabel(null), isNull);
    });

    test('drawing gets a pencil, building gets a hammer', () {
      // A hammer over an image request is the wrong verb, and a wrong verb in
      // an animation is as noticeable as one in a sentence.
      expect(buildingTool(StudioType.imageStudio), BuildingTool.pencil);
      expect(buildingTool(StudioType.brandPackStudio), BuildingTool.pencil);
      expect(buildingTool(StudioType.codeStudio), BuildingTool.hammer);
      expect(buildingTool(StudioType.deckStudio), BuildingTool.hammer);
    });

    test('every studio is decided one way or the other', () {
      // A studio added without a decision here would silently fall back to
      // dots; the switch is exhaustive, so this is really a reminder that the
      // choice is deliberate for each one.
      for (final studio in StudioType.values) {
        expect(() => buildingLabel(studio), returnsNormally, reason: '$studio');
      }
    });
  });
}

void _priming() {
  test('speech is unlocked before anything is awaited', () {
    // iOS Safari refuses speechSynthesis.speak() unless it has been called
    // once from inside a user gesture. Voice mode speaks its reply from an
    // async callback minutes later, so on an iPhone the model answered and
    // nothing came out — everything else worked, which is why it read as
    // "replies silently" rather than as broken.
    //
    // The unlock has to happen synchronously in the tap that opened voice
    // mode. Asserted on the source because the ordering *is* the fix: an
    // await before it and the gesture context is gone.
    final source = File('lib/features/voice/voice_mode_controller.dart')
        .readAsStringSync();
    final start = source.indexOf('Future<void> start() async {');
    expect(start, greaterThan(-1));
    final body = source.substring(start);
    final prime = body.indexOf('TtsService.prime()');
    final firstAwait = body.indexOf('await ');

    expect(prime, greaterThan(-1), reason: 'the unlock must exist');
    expect(prime, lessThan(firstAwait),
        reason: 'the unlock must come before the first await');
  });
}
