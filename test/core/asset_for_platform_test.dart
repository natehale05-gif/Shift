import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/core/update/asset_for_platform.dart';
import 'package:shift_ai/core/update/update_check.dart';

ReleaseAsset _a(String name) =>
    ReleaseAsset(name: name, downloadUrl: 'https://x/$name', size: 1);

/// What `release.yml` attaches today.
final _fullRelease = [
  _a('SHIFT-AI-macos.dmg'),
  _a('SHIFT-AI-windows.zip'),
  _a('SHIFT-AI-linux-x64.tar.gz'),
  _a('SHIFT-AI-android.apk'),
];

void main() {
  group('assetForPlatform', () {
    test('each platform gets its own asset', () {
      expect(assetForPlatform(_fullRelease, 'linux')!.name,
          'SHIFT-AI-linux-x64.tar.gz');
      expect(assetForPlatform(_fullRelease, 'windows')!.name,
          'SHIFT-AI-windows.zip');
      expect(assetForPlatform(_fullRelease, 'macos')!.name,
          'SHIFT-AI-macos.dmg');
      expect(assetForPlatform(_fullRelease, 'android')!.name,
          'SHIFT-AI-android.apk');
    });

    test('a release with nothing for this platform yields null', () {
      // The failure that matters is downloading the *wrong* file, not
      // missing one -- so a partial release must never fall through to
      // whatever asset happens to be first.
      final noLinux = _fullRelease.where((a) => !a.name.endsWith('.gz'));
      expect(assetForPlatform(noLinux.toList(), 'linux'), isNull);

      final onlyDesktop =
          _fullRelease.where((a) => !a.name.endsWith('.apk')).toList();
      expect(assetForPlatform(onlyDesktop, 'android'), isNull);
    });

    test('an empty release yields null', () {
      expect(assetForPlatform(const [], 'linux'), isNull);
    });

    test('a platform this project does not package yields null', () {
      expect(assetForPlatform(_fullRelease, 'ios'), isNull);
      expect(assetForPlatform(_fullRelease, 'fuchsia'), isNull);
      expect(assetForPlatform(_fullRelease, 'web'), isNull);
      expect(assetForPlatform(_fullRelease, ''), isNull);
    });

    test('matching is by suffix, so a renamed asset still resolves', () {
      final renamed = [_a('shift-ai_0.2.0_amd64.tar.gz')];
      expect(assetForPlatform(renamed, 'linux')!.name,
          'shift-ai_0.2.0_amd64.tar.gz');
    });

    test('case does not matter', () {
      expect(assetForPlatform([_a('SHIFT-AI-MACOS.DMG')], 'macos'), isNotNull);
    });
  });

  group('installModeFor', () {
    test('Linux and Windows can replace themselves silently', () {
      expect(installModeFor('linux'), InstallMode.replaceAndRelaunch);
      expect(installModeFor('windows'), InstallMode.replaceAndRelaunch);
    });

    test('macOS and Android hand off to the OS', () {
      // Not a shortcut: an unsigned .app replacement re-triggers Gatekeeper,
      // and Android has no silent sideload path at all.
      expect(installModeFor('macos'), InstallMode.handOffToSystem);
      expect(installModeFor('android'), InstallMode.handOffToSystem);
    });

    test('everything else, including web, is unsupported', () {
      expect(installModeFor('web'), InstallMode.unsupported);
      expect(installModeFor('ios'), InstallMode.unsupported);
    });
  });
}
