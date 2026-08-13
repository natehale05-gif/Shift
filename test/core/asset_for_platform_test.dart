import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/core/update/asset_for_platform.dart';
import 'package:shift/core/update/update_check.dart';

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

    test('macOS hands the download to the OS', () {
      // Not a shortcut: replacing an unsigned .app re-triggers Gatekeeper, so
      // an in-place swap would trade one click for a more alarming one.
      expect(installModeFor('macos'), InstallMode.handOffToSystem);
    });

    test('Android goes to the page and downloads nothing', () {
      // The decision this wave turns on. The app this replaced handed an APK
      // to the package installer, which needs `REQUEST_INSTALL_PACKAGES` —
      // prohibited by Play's Device and Network Abuse policy, and one of the
      // reasons there was a rebuild. Asserted as `handOffToPage` and not
      // merely "not handOffToSystem", so a later edit cannot drift back into
      // downloading an APK it may not install.
      expect(installModeFor('android'), InstallMode.handOffToPage);
      expect(installModeFor('android'), isNot(InstallMode.handOffToSystem));
    });

    test('no code here asks for the permission that would allow it', () async {
      // The manifest is guarded in CI; this guards the Dart, because the
      // permission would arrive with the code that needed it. A grep, because
      // the property is an absence and there is nothing to call.
      final dir = Directory('lib');
      final offenders = <String>[];
      await for (final entry in dir.list(recursive: true)) {
        if (entry is! File || !entry.path.endsWith('.dart')) continue;
        final text = await entry.readAsString();
        // This file names the permission in prose to explain why it is absent;
        // what must not appear is a call that uses it.
        if (text.contains('installApk') ||
            text.contains('android.permission.REQUEST_INSTALL_PACKAGES')) {
          offenders.add(entry.path);
        }
      }
      expect(offenders, isEmpty);
    });

    test('everything else, including web, is unsupported', () {
      expect(installModeFor('web'), InstallMode.unsupported);
      expect(installModeFor('ios'), InstallMode.unsupported);
    });
  });
}
