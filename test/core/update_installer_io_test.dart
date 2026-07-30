import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/core/update/update_installer.dart' show InstallOutcome;
import 'package:shift_ai/core/update/update_installer_io.dart';

const _executable = 'shift_ai';

/// A tar.gz shaped like the one `release.yml` produces:
/// `tar -czf … -C bundle .`, so every entry carries a `./` prefix.
List<int> _bundleTarGz({
  bool withExecutable = true,
  List<String> extra = const [],
}) {
  final archive = Archive();
  if (withExecutable) {
    archive.addFile(
      ArchiveFile('./$_executable', 4, [1, 2, 3, 4])..mode = 493, // 0755
    );
  }
  archive.addFile(ArchiveFile('./data/flutter_assets/AssetManifest.json', 2, [
    123,
    125,
  ]));
  for (final name in extra) {
    archive.addFile(ArchiveFile(name, 1, [0]));
  }
  return GZipEncoder().encode(TarEncoder().encode(archive))!;
}

void main() {
  late Directory root;
  late Directory install;
  late Directory staged;

  setUp(() {
    root = Directory.systemTemp.createTempSync('shift_update_test');
    install = Directory('${root.path}/SHIFT-AI-linux-x64')
      ..createSync(recursive: true);
    File('${install.path}/$_executable').writeAsStringSync('the old build');
    staged = Directory('${install.path}_staged');
    useInstallLocation(install.path, _executable);
  });

  tearDown(() {
    resetInstallLocation();
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('a good bundle stages beside the install, leaving it untouched',
      () async {
    final outcome = await stageArchiveBytes(_bundleTarGz(), isZip: false);

    expect(outcome, InstallOutcome.staged);
    expect(File('${staged.path}/$_executable').existsSync(), isTrue);
    expect(
      File('${staged.path}/data/flutter_assets/AssetManifest.json')
          .existsSync(),
      isTrue,
      reason: 'nested entries survive the ./ prefix strip',
    );
    // The running install is not touched until the swap script runs.
    expect(File('${install.path}/$_executable').readAsStringSync(),
        'the old build');
    expect(hasStagedUpdate(), isTrue);
  });

  test('an archive without the executable is refused and cleaned up',
      () async {
    // The scenario that would brick an install: a wrong-platform archive, or
    // one that unpacked into a wrapper directory. Refusing is the whole
    // point -- there must be nothing left for the swap to pick up.
    final outcome =
        await stageArchiveBytes(_bundleTarGz(withExecutable: false), isZip: false);

    expect(outcome, InstallOutcome.failed);
    expect(staged.existsSync(), isFalse);
    expect(hasStagedUpdate(), isFalse);
    expect(File('${install.path}/$_executable').readAsStringSync(),
        'the old build');
  });

  test('a truncated archive is refused', () async {
    final good = _bundleTarGz();
    final outcome = await stageArchiveBytes(
      good.sublist(0, good.length ~/ 2),
      isZip: false,
    );

    expect(outcome, InstallOutcome.failed);
    expect(staged.existsSync(), isFalse);
  });

  test('bytes that are not an archive at all are refused', () async {
    final outcome = await stageArchiveBytes(
      'this is an error page, not a tarball'.codeUnits,
      isZip: false,
    );

    expect(outcome, InstallOutcome.failed);
    expect(staged.existsSync(), isFalse);
  });

  test('an entry cannot escape the staging directory', () async {
    await stageArchiveBytes(
      _bundleTarGz(extra: ['../../escaped.txt', './../sibling.txt']),
      isZip: false,
    );

    expect(File('${root.path}/escaped.txt').existsSync(), isFalse);
    expect(File('${install.path}_escaped.txt').existsSync(), isFalse);
    expect(File('${root.path}/sibling.txt').existsSync(), isFalse);
  });

  test('staging twice replaces the previous staging rather than merging',
      () async {
    await stageArchiveBytes(_bundleTarGz(extra: ['./stale.txt']), isZip: false);
    expect(File('${staged.path}/stale.txt').existsSync(), isTrue);

    await stageArchiveBytes(_bundleTarGz(), isZip: false);
    expect(File('${staged.path}/stale.txt').existsSync(), isFalse,
        reason: 'a leftover file from an abandoned update must not survive');
    expect(File('${staged.path}/$_executable').existsSync(), isTrue);
  });

  test('applyStagedUpdate does nothing when there is nothing staged',
      () async {
    expect(hasStagedUpdate(), isFalse);
    expect(await applyStagedUpdate(), isFalse);
  });

  group('canReplaceInPlace', () {
    test('a writable install directory can replace itself', () {
      expect(canReplaceInPlace(), isTrue);
    });

    test('a read-only parent cannot', () async {
      // What a .deb install looks like: the bundle lives under root-owned
      // /opt, so the sibling staging directory can never be created. The
      // probe has to notice *before* the download, or the app spends 23 MB
      // to arrive at a failure it could have predicted.
      final locked = Directory('${root.path}/locked')..createSync();
      Directory('${locked.path}/SHIFT-AI-linux-x64').createSync();
      useInstallLocation('${locked.path}/SHIFT-AI-linux-x64', _executable);
      await Process.run('chmod', ['555', locked.path]);

      addTearDown(() => Process.run('chmod', ['755', locked.path]));

      // Running the suite as root defeats permission bits entirely, so this
      // assertion is only meaningful for an unprivileged user.
      final probe = File('${locked.path}/probe');
      var writable = true;
      try {
        probe.writeAsStringSync('');
        probe.deleteSync();
      } catch (_) {
        writable = false;
      }

      if (writable) {
        markTestSkipped('running as root: permission bits do not apply');
        return;
      }
      expect(canReplaceInPlace(), isFalse);
    });

    test('a parent that does not exist cannot', () {
      useInstallLocation('/definitely/not/here/SHIFT-AI', _executable);
      expect(canReplaceInPlace(), isFalse);
    });
  });

  group('a swap that fails is not retried forever', () {
    // The Windows report: the app kept quitting, flashing a console window,
    // and coming back unchanged. A staged tree that survived a failed swap was
    // still "pending" on the next launch, so every launch tried it again.
    File marker() => File('${staged.path}.attempted');

    test('a second attempt at the same staged tree is refused', () async {
      await stageArchiveBytes(_bundleTarGz(), isZip: false);
      expect(hasStagedUpdate(), isTrue);

      // Stand in for the first attempt having happened and not worked.
      marker().writeAsStringSync('2026-07-30T12:00:00.000');

      expect(await applyStagedUpdate(), isFalse,
          reason: 'the tree already had its turn');
    });

    test('the refused tree is discarded, so the app boots normally', () async {
      await stageArchiveBytes(_bundleTarGz(), isZip: false);
      marker().writeAsStringSync('x');

      await applyStagedUpdate();

      expect(staged.existsSync(), isFalse);
      expect(marker().existsSync(), isFalse);
      expect(hasStagedUpdate(), isFalse,
          reason: 'nothing left to retry on the next launch');
    });

    test('the install itself is never touched by the refusal', () async {
      await stageArchiveBytes(_bundleTarGz(), isZip: false);
      marker().writeAsStringSync('x');

      await applyStagedUpdate();

      expect(File('${install.path}/$_executable').readAsStringSync(),
          'the old build');
    });

    test('a later update stages cleanly after a refusal', () async {
      // The marker must not outlive the tree it refers to, or the *next* real
      // update could never be applied either.
      await stageArchiveBytes(_bundleTarGz(), isZip: false);
      marker().writeAsStringSync('x');
      await applyStagedUpdate();

      final outcome = await stageArchiveBytes(_bundleTarGz(), isZip: false);
      expect(outcome, InstallOutcome.staged);
      expect(hasStagedUpdate(), isTrue);
      expect(marker().existsSync(), isFalse);
    });

    test('with nothing staged there is nothing to attempt', () async {
      expect(await applyStagedUpdate(), isFalse);
    });
  });
}
