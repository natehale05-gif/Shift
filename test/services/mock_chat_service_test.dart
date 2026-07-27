import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/services/studio_response_bank.dart';

void main() {
  group('StudioResponseBank.detectStudio', () {
    test('routes image keywords to Image Studio', () {
      expect(StudioResponseBank.detectStudio('make me a logo'), StudioType.imageStudio);
      expect(StudioResponseBank.detectStudio('need a product shot for the launch'), StudioType.imageStudio);
    });

    test('routes video keywords to Video Studio', () {
      expect(StudioResponseBank.detectStudio('cut a 30-second video ad'), StudioType.videoStudio);
      expect(StudioResponseBank.detectStudio('I need a trailer'), StudioType.videoStudio);
    });

    test('routes short-form keywords to ShortReels Studio', () {
      expect(StudioResponseBank.detectStudio('cut a short reel for TikTok'), StudioType.shortReelsStudio);
      expect(StudioResponseBank.detectStudio('a pack of shorts for launch'), StudioType.shortReelsStudio);
    });

    test('routes voice keywords to Voice Studio', () {
      expect(StudioResponseBank.detectStudio('clone my voice for this'), StudioType.voiceStudio);
      expect(StudioResponseBank.detectStudio('narrate this script'), StudioType.voiceStudio);
    });

    test('routes avatar keywords to Avatar Studio', () {
      expect(StudioResponseBank.detectStudio('a talking head avatar of me'), StudioType.avatarStudio);
      expect(StudioResponseBank.detectStudio('make a spokesperson video'), StudioType.avatarStudio);
    });

    test('routes translate/deck/brand keywords to their studios', () {
      expect(StudioResponseBank.detectStudio('translate this to Spanish'), StudioType.translateStudio);
      expect(StudioResponseBank.detectStudio('make me a slide deck'), StudioType.deckStudio);
      expect(StudioResponseBank.detectStudio('build a brand pack'), StudioType.brandPackStudio);
    });

    test('routes music keywords to Music Studio', () {
      expect(StudioResponseBank.detectStudio('drop a lo-fi beat'), StudioType.musicStudio);
      expect(StudioResponseBank.detectStudio('I need a soundtrack'), StudioType.musicStudio);
    });

    test('routes copy keywords to Copy & Scripts Studio', () {
      expect(StudioResponseBank.detectStudio('write me a sales letter'), StudioType.copyScriptsStudio);
      expect(StudioResponseBank.detectStudio('need a punchy hook'), StudioType.copyScriptsStudio);
      expect(StudioResponseBank.detectStudio('draft an ad script for the launch'), StudioType.copyScriptsStudio);
    });

    test('routes code keywords to Code Studio', () {
      expect(StudioResponseBank.detectStudio('write a python function to reverse a string'), StudioType.codeStudio);
      expect(StudioResponseBank.detectStudio('debug this for loop'), StudioType.codeStudio);
      expect(StudioResponseBank.detectStudio('write a shell script to backup files'), StudioType.codeStudio);
    });

    test('bare "script" reads as Code Studio, not Copy & Scripts', () {
      expect(StudioResponseBank.detectStudio('write me a script to rename files'), StudioType.codeStudio);
    });

    test('falls back to middleware when nothing matches', () {
      expect(StudioResponseBank.detectStudio('what time is it in Tokyo?'), StudioType.middleware);
    });

    test('is case-insensitive', () {
      expect(StudioResponseBank.detectStudio('MAKE ME A LOGO'), StudioType.imageStudio);
    });
  });

  group('StudioResponseBank.seedFromString', () {
    test('is deterministic for the same input', () {
      final a = StudioResponseBank.seedFromString('same prompt');
      final b = StudioResponseBank.seedFromString('same prompt');
      expect(a, b);
    });

    test('differs for different input', () {
      final a = StudioResponseBank.seedFromString('prompt one');
      final b = StudioResponseBank.seedFromString('prompt two');
      expect(a, isNot(b));
    });
  });
}
