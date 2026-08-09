import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift/core/device/device_class.dart';

void main() {
  group('device class', () {
    test('a phone is a phone', () {
      // 393 x 852 — a current handset, portrait.
      expect(
        deviceClassOf(platform: TargetPlatform.iOS, shortestSide: 393),
        DeviceClass.phone,
      );
      expect(
        deviceClassOf(platform: TargetPlatform.android, shortestSide: 412),
        DeviceClass.phone,
      );
    });

    test('a phone in landscape is still a phone', () {
      // The regression this whole function exists to prevent. `shortestSide`
      // is orientation-independent by construction, so rotating a handset
      // cannot promote it into the IDE — which, at 393 logical pixels tall,
      // would be unusable.
      expect(
        deviceClassOf(platform: TargetPlatform.iOS, shortestSide: 393),
        DeviceClass.phone,
      );
    });

    test('an iPad is a tablet, and gets the roomy surfaces', () {
      // 744 is the smallest current iPad's shortest side; 1024 is a Pro.
      for (final side in [744.0, 820.0, 1024.0]) {
        final result =
            deviceClassOf(platform: TargetPlatform.iOS, shortestSide: side);
        expect(result, DeviceClass.tablet, reason: '$side');
        expect(result.isRoomy, isTrue, reason: '$side');
      }
    });

    test('a desktop window dragged narrow is still a desktop', () {
      // The other half of the point. If this answered from window width, then
      // narrowing a window would swap someone's editor for a task list while
      // they were using it — the app changing out from under them, not a
      // layout adapting.
      for (final side in [380.0, 500.0, 2400.0]) {
        expect(
          deviceClassOf(platform: TargetPlatform.macOS, shortestSide: side),
          DeviceClass.desktop,
          reason: '$side',
        );
      }
      expect(
        deviceClassOf(platform: TargetPlatform.windows, shortestSide: 320),
        DeviceClass.desktop,
      );
      expect(
        deviceClassOf(platform: TargetPlatform.linux, shortestSide: 320),
        DeviceClass.desktop,
      );
    });

    test('the boundary is where no real device sits', () {
      // Chosen to fall in a gap rather than next to something, so a slightly
      // larger phone next year does not silently become a tablet.
      expect(
        deviceClassOf(
            platform: TargetPlatform.android,
            shortestSide: kTabletShortestSide - 0.1),
        DeviceClass.phone,
      );
      expect(
        deviceClassOf(
            platform: TargetPlatform.android,
            shortestSide: kTabletShortestSide),
        DeviceClass.tablet,
      );
    });

    test('the user override beats every other signal', () {
      // A rule with no escape hatch is one that stays wrong for whoever it is
      // wrong about. Both directions, because both complaints are plausible:
      // a small tablet used one-handed, and a large phone in a stand.
      expect(
        deviceClassOf(
          platform: TargetPlatform.macOS,
          shortestSide: 1440,
          override: DeviceClass.phone,
        ),
        DeviceClass.phone,
      );
      expect(
        deviceClassOf(
          platform: TargetPlatform.iOS,
          shortestSide: 393,
          override: DeviceClass.desktop,
        ),
        DeviceClass.desktop,
      );
    });

    test('every platform is decided', () {
      // The switch is exhaustive, so a new TargetPlatform would fail to
      // compile rather than fall through to a default that guesses.
      for (final platform in TargetPlatform.values) {
        expect(
          () => deviceClassOf(platform: platform, shortestSide: 800),
          returnsNormally,
          reason: '$platform',
        );
      }
    });

    test('only a phone is not roomy', () {
      expect(DeviceClass.phone.isRoomy, isFalse);
      expect(DeviceClass.tablet.isRoomy, isTrue);
      expect(DeviceClass.desktop.isRoomy, isTrue);
    });
  });
}
