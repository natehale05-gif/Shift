import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/turn/live_mode.dart';

void main() {
  group('what the app says it is', () {
    test('a membership is not demo mode', () {
      // The label that was wrong for as long as memberships existed. Both the
      // chip and the line under the composer asked "has this device stored a
      // key", so someone watching a real model write a real page was told
      // underneath it that responses were simulated.
      final described = describeLive(liveCapability(
        hasOwnKey: false,
        hasMembership: true,
      ));

      expect(described.chip, 'Live');
      expect(described.footer, isNot(contains('demo mode')));
    });

    test('and it says which half is not real', () {
      // A member watching a real page get built and then a placeholder image
      // appear should be told which of those was real, rather than working it
      // out — that is the whole reason this footer survives at all.
      final described = describeLive(LiveCapability.membershipText);

      expect(described.footer, contains('Images and voice are simulated'));
    });

    test('no key and no plan is still demo mode', () {
      final described = describeLive(liveCapability(
        hasOwnKey: false,
        hasMembership: false,
      ));

      expect(described.chip, 'Simulated');
      expect(described.footer, contains('demo mode'));
    });

    test('a stored key wins, because it is the broader claim', () {
      // Billing spends the membership first — they pay for it monthly. But a
      // stored key is the only thing that makes an image or a voice turn real,
      // so it is the description that stays true.
      expect(liveCapability(hasOwnKey: true, hasMembership: true),
          LiveCapability.ownKeys);
      expect(describeLive(LiveCapability.ownKeys).footer, isNull,
          reason: 'a caution nobody reads twice is furniture');
    });

    test('every capability has wording', () {
      for (final capability in LiveCapability.values) {
        final described = describeLive(capability);
        expect(described.chip, isNotEmpty, reason: '$capability');
        expect(described.tooltip, isNotEmpty, reason: '$capability');
      }
    });

    test('the two live states are not described identically', () {
      // Both say "Live", and they must not say the same thing beyond that:
      // one covers images and one does not, which is the difference a member
      // needs.
      expect(describeLive(LiveCapability.membershipText).tooltip,
          isNot(describeLive(LiveCapability.ownKeys).tooltip));
    });
  });
}
