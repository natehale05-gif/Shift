import 'package:shift_ai/turn/studio_detection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/studio_type.dart';
import 'package:shift_ai/features/studios/studio_response_bank.dart';

void main() {
  group('StudioDetection.detectStudio', () {
    test('routes image keywords to Image Studio', () {
      expect(StudioDetection.detectStudio('make me a logo'), StudioType.imageStudio);
      expect(StudioDetection.detectStudio('need a product shot for the launch'), StudioType.imageStudio);
    });

    test('routes video keywords to Video Studio', () {
      expect(StudioDetection.detectStudio('cut a 30-second video ad'), StudioType.videoStudio);
      expect(StudioDetection.detectStudio('I need a trailer'), StudioType.videoStudio);
    });

    test('routes short-form keywords to ShortReels Studio', () {
      expect(StudioDetection.detectStudio('cut a short reel for TikTok'), StudioType.shortReelsStudio);
      expect(StudioDetection.detectStudio('a pack of shorts for launch'), StudioType.shortReelsStudio);
    });

    test('routes voice keywords to Voice Studio', () {
      expect(StudioDetection.detectStudio('clone my voice for this'), StudioType.voiceStudio);
      expect(StudioDetection.detectStudio('narrate this script'), StudioType.voiceStudio);
    });

    test('routes avatar keywords to Avatar Studio', () {
      expect(StudioDetection.detectStudio('a talking head avatar of me'), StudioType.avatarStudio);
      expect(StudioDetection.detectStudio('make a spokesperson video'), StudioType.avatarStudio);
    });

    test('routes translate/deck/brand keywords to their studios', () {
      expect(StudioDetection.detectStudio('translate this to Spanish'), StudioType.translateStudio);
      expect(StudioDetection.detectStudio('make me a slide deck'), StudioType.deckStudio);
      expect(StudioDetection.detectStudio('build a brand pack'), StudioType.brandPackStudio);
    });

    test('routes music keywords to Music Studio', () {
      expect(StudioDetection.detectStudio('drop a lo-fi beat'), StudioType.musicStudio);
      expect(StudioDetection.detectStudio('I need a soundtrack'), StudioType.musicStudio);
    });

    test('routes copy keywords to Copy & Scripts Studio', () {
      expect(StudioDetection.detectStudio('write me a sales letter'), StudioType.copyScriptsStudio);
      expect(StudioDetection.detectStudio('need a punchy hook'), StudioType.copyScriptsStudio);
      expect(StudioDetection.detectStudio('draft an ad script for the launch'), StudioType.copyScriptsStudio);
    });

    test('routes code keywords to Code Studio', () {
      expect(StudioDetection.detectStudio('write a python function to reverse a string'), StudioType.codeStudio);
      expect(StudioDetection.detectStudio('debug this for loop'), StudioType.codeStudio);
      expect(StudioDetection.detectStudio('write a shell script to backup files'), StudioType.codeStudio);
    });

    test('bare "script" reads as Code Studio, not Copy & Scripts', () {
      expect(StudioDetection.detectStudio('write me a script to rename files'), StudioType.codeStudio);
    });

    test('falls back to middleware when nothing matches', () {
      expect(StudioDetection.detectStudio('what time is it in Tokyo?'), StudioType.middleware);
    });

    test('is case-insensitive', () {
      expect(StudioDetection.detectStudio('MAKE ME A LOGO'), StudioType.imageStudio);
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
