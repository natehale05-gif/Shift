import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/core/update/release_version.dart';

void main() {
  group('isNewerRelease', () {
    test('a higher tag is newer', () {
      expect(isNewerRelease('0.1.0', 'v0.1.1'), isTrue);
      expect(isNewerRelease('0.1.0', 'v0.2.0'), isTrue);
      expect(isNewerRelease('0.1.0', 'v1.0.0'), isTrue);
    });

    test('the same version is not newer', () {
      expect(isNewerRelease('0.1.0', 'v0.1.0'), isFalse);
      // The `v` is decoration, not part of the version.
      expect(isNewerRelease('0.1.0', '0.1.0'), isFalse);
    });

    test('an older tag is not newer', () {
      expect(isNewerRelease('0.2.0', 'v0.1.9'), isFalse);
      expect(isNewerRelease('1.0.0', 'v0.9.9'), isFalse);
    });

    test('a build number is not a version bump', () {
      // pubspec versions carry `+build`; tags do not. Reading `0.1.0+1` as
      // newer than `v0.1.0` would have every downloaded copy reinstalling
      // the version it is already running, on every check, forever.
      expect(isNewerRelease('0.1.0+1', 'v0.1.0'), isFalse);
      expect(isNewerRelease('0.1.0+9', 'v0.1.0'), isFalse);
      expect(isNewerRelease('0.1.0+1', 'v0.1.1'), isTrue);
    });

    test('segments compare numerically, not lexically', () {
      expect(isNewerRelease('0.9.0', 'v0.10.0'), isTrue);
      expect(isNewerRelease('0.10.0', 'v0.9.0'), isFalse);
      expect(isNewerRelease('1.0.9', 'v1.0.10'), isTrue);
    });

    test('a missing segment is zero', () {
      expect(isNewerRelease('1.0', 'v1.0.0'), isFalse);
      expect(isNewerRelease('1.0', 'v1.0.1'), isTrue);
      expect(isNewerRelease('1.0.0', 'v1.1'), isTrue);
    });

    test('anything unparseable is not an update', () {
      // Defaulting to false costs a missed update; defaulting the other way
      // replaces a working install off a string nobody validated.
      for (final tag in ['', '   ', 'latest', 'v', 'v1.x', 'nightly', 'v-1.0']) {
        expect(isNewerRelease('0.1.0', tag), isFalse, reason: 'tag "$tag"');
      }
    });

    test('an unknown running version never offers an update', () {
      // PackageInfo can come back empty on a platform with no packaged
      // manifest. Comparing against nothing must not mean "everything is
      // newer".
      expect(isNewerRelease('', 'v9.9.9'), isFalse);
      expect(isNewerRelease('unknown', 'v9.9.9'), isFalse);
    });

    test('a pre-release tag is treated as its base version', () {
      expect(isNewerRelease('0.1.0', 'v0.1.0-beta.2'), isFalse);
      expect(isNewerRelease('0.1.0', 'v0.2.0-rc1'), isTrue);
    });
  });
}
