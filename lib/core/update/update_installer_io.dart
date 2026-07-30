import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../platform/open_url.dart';
import 'asset_for_platform.dart';
import 'update_check.dart';
import 'update_installer.dart' show InstallOutcome;

/// Desktop and Android installation.
///
/// Linux and Windows ship as a self-contained directory, so an update is a
/// directory swap: unpack beside the install, then rename. macOS and Android
/// cannot be silent for unsigned software, so they download the installer and
/// hand it to the OS.
///
/// The swap is the most destructive thing this app does, so it is guarded
/// structurally rather than carefully:
///
/// * a download whose length does not match the release's is discarded
///   before anything is unpacked;
/// * the unpacked tree must contain the running executable's own name, so a
///   half-extracted or wrong-platform archive can never replace a working
///   install;
/// * the swap renames rather than deletes, and rolls the backup back if the
///   second rename fails. The old install is never removed before the new
///   one is in place.

/// Set by the Android install-intent channel; see [_handOff].
const _androidChannel = 'club.shiftai.app/installer';

InstallMode installMode() => installModeFor(Platform.operatingSystem);

/// Where the running app lives, e.g. `…/SHIFT-AI-linux-x64`.
Directory get _installDir =>
    Directory(_installOverride ?? File(Platform.resolvedExecutable).parent.path);

/// The unpacked next version, waiting beside it.
Directory get _stagedDir => Directory('${_installDir.path}_staged');

/// The name the swapped-in tree has to contain for the swap to be allowed.
String get _executableName =>
    _executableOverride ??
    Platform.resolvedExecutable.split(Platform.pathSeparator).last;

String? _installOverride;
String? _executableOverride;

/// Points the staging logic at a scratch directory so its guards can be
/// tested without a real install to endanger. Under `flutter test` the
/// "install" would otherwise be wherever the Dart VM binary lives.
@visibleForTesting
void useInstallLocation(String directory, String executableName) {
  _installOverride = directory;
  _executableOverride = executableName;
}

@visibleForTesting
void resetInstallLocation() {
  _installOverride = null;
  _executableOverride = null;
}

/// Unpacks [bytes] into the staging directory, or refuses to.
///
/// Split out from the download so the two guards that protect a working
/// install — the executable must be present, and no entry may escape the
/// staging directory — are testable without a network or a platform channel.
@visibleForTesting
Future<InstallOutcome> stageArchiveBytes(
  List<int> bytes, {
  required bool isZip,
}) async =>
    _unpack(bytes, isZip: isZip);

bool hasStagedUpdate() {
  try {
    return _stagedDir.existsSync() &&
        File('${_stagedDir.path}${Platform.pathSeparator}$_executableName')
            .existsSync();
  } catch (_) {
    return false;
  }
}

/// Marks that a swap was already attempted for the tree currently staged.
///
/// Without this the app could not fail: a swap that did not go through left
/// the staged directory in place, so the next launch attempted it again, quit
/// to do so, and came back to the same state — forever. On Windows each
/// attempt also flashed a console window, which is what made the loop
/// obvious. One attempt per staged build; then the staged tree is discarded
/// and the app starts normally.
File get _attemptMarker => File('${_stagedDir.path}.attempted');

bool _swapAlreadyAttempted() {
  try {
    return _attemptMarker.existsSync();
  } catch (_) {
    return false;
  }
}

/// Throws away a staged update that could not be applied, so the app boots
/// normally instead of retrying forever. The next check re-downloads it.
void _discardStagedUpdate() {
  try {
    if (_stagedDir.existsSync()) _stagedDir.deleteSync(recursive: true);
  } catch (_) {
    // Better to start the app than to fail on cleanup.
  }
  try {
    if (_attemptMarker.existsSync()) _attemptMarker.deleteSync();
  } catch (_) {
    // Same.
  }
}

/// Whether this copy is allowed to replace itself in place.
///
/// A `.deb` unpacks into `/opt`, and a Windows all-users install lands in
/// `Program Files` — both root-owned. The swap would fail there, and failing
/// *after* a 23 MB download, with a message that reads like the check itself
/// broke, is the worst of the available outcomes. Probing first turns it into
/// an accurate sentence and a working link.
///
/// Probed by actually writing, not by reading permission bits: ownership,
/// ACLs, read-only mounts and Windows semantics do not reduce to a mode check.
bool canReplaceInPlace() {
  if (installModeFor(Platform.operatingSystem) !=
      InstallMode.replaceAndRelaunch) {
    return true; // Hand-off platforms never touch the install directory.
  }
  try {
    final parent = _installDir.parent;
    if (!parent.existsSync()) return false;
    final probe = File('${parent.path}${Platform.pathSeparator}'
        '.shift_ai_write_probe_${DateTime.now().microsecondsSinceEpoch}');
    probe.writeAsStringSync('');
    probe.deleteSync();
    return true;
  } catch (_) {
    return false;
  }
}

Future<InstallOutcome> downloadAndInstall(
  ReleaseAsset asset, {
  void Function(double progress)? onProgress,
  http.Client Function()? clientFactory,
}) async {
  final mode = installMode();
  if (mode == InstallMode.unsupported) return InstallOutcome.failed;
  // Checked before the download, not after: there is no point spending the
  // bandwidth on an update this copy cannot apply.
  if (!canReplaceInPlace()) return InstallOutcome.notPermitted;

  final file = await _download(asset, onProgress, clientFactory);
  if (file == null) return InstallOutcome.failed;

  try {
    return mode == InstallMode.replaceAndRelaunch
        ? await _stage(file, asset)
        : await _handOff(file);
  } catch (_) {
    return InstallOutcome.failed;
  }
}

/// Streams the asset to a temp file, rejecting anything that does not arrive
/// whole. A truncated archive that reached the unpacker would look like a
/// valid-but-incomplete install.
Future<File?> _download(
  ReleaseAsset asset,
  void Function(double)? onProgress,
  http.Client Function()? clientFactory,
) async {
  final client = (clientFactory ?? http.Client.new)();
  IOSink? sink;
  try {
    final request = http.Request('GET', Uri.parse(asset.downloadUrl))
      ..followRedirects = true;
    final response = await client.send(request);
    if (response.statusCode != 200) return null;

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}${asset.name}');
    sink = file.openWrite();

    var received = 0;
    await for (final chunk in response.stream) {
      received += chunk.length;
      sink.add(chunk);
      onProgress?.call(asset.size > 0 ? received / asset.size : 0);
    }
    await sink.flush();
    await sink.close();
    sink = null;

    if (await file.length() != asset.size) {
      await file.delete();
      return null;
    }
    return file;
  } catch (_) {
    await sink?.close();
    return null;
  } finally {
    client.close();
  }
}

Future<InstallOutcome> _stage(File archiveFile, ReleaseAsset asset) async {
  final outcome = await _unpack(
    await archiveFile.readAsBytes(),
    isZip: asset.name.toLowerCase().endsWith('.zip'),
  );
  if (outcome == InstallOutcome.staged) await archiveFile.delete();
  return outcome;
}

/// Unpacks beside the install, refusing to leave anything behind unless the
/// result actually looks like this app.
Future<InstallOutcome> _unpack(List<int> bytes, {required bool isZip}) async {
  final staged = _stagedDir;
  if (await staged.exists()) await staged.delete(recursive: true);
  await staged.create(recursive: true);

  final Archive archive;
  try {
    archive = isZip
        ? ZipDecoder().decodeBytes(bytes)
        : TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  } catch (_) {
    await staged.delete(recursive: true);
    return InstallOutcome.failed;
  }

  for (final entry in archive) {
    // `tar -C bundle .` writes entries as `./shift_ai`; strip that, and
    // refuse any path trying to climb out of the staging directory.
    final relative = entry.name.replaceFirst(RegExp(r'^\./'), '');
    if (relative.isEmpty || relative.contains('..')) continue;

    final path = '${staged.path}${Platform.pathSeparator}'
        '${relative.replaceAll('/', Platform.pathSeparator)}';
    if (!entry.isFile) {
      await Directory(path).create(recursive: true);
      continue;
    }
    final out = File(path);
    await out.parent.create(recursive: true);
    await out.writeAsBytes(entry.content as List<int>, flush: true);

    // The tar records the executable bit; a zip on Windows does not need it.
    if (!Platform.isWindows && entry.mode & 0x49 != 0) {
      await Process.run('chmod', ['+x', path]);
    }
  }

  final executable =
      File('${staged.path}${Platform.pathSeparator}$_executableName');
  if (!await executable.exists()) {
    // Wrong archive, or one that unpacked into a wrapper directory. Either
    // way it is not something to swap a working install for.
    await staged.delete(recursive: true);
    return InstallOutcome.failed;
  }
  if (!Platform.isWindows) {
    await Process.run('chmod', ['+x', executable.path]);
  }
  return InstallOutcome.staged;
}

/// macOS and Android: open the downloaded installer and let the OS ask.
Future<InstallOutcome> _handOff(File file) async {
  if (Platform.isAndroid) {
    // The system package installer is reached through an intent, which needs
    // a FileProvider URI — so it goes through the runner rather than
    // url_launcher. See MainActivity.kt.
    const channel = MethodChannel(_androidChannel);
    final ok = await channel.invokeMethod<bool>('installApk', file.path);
    return ok == true ? InstallOutcome.handedOff : InstallOutcome.failed;
  }
  // macOS: Finder mounts the .dmg and the user drags it across once. An
  // in-place replacement would still re-trigger Gatekeeper while unsigned,
  // so it would trade one click for a more alarming one.
  openUrl(file.uri.toString());
  return InstallOutcome.handedOff;
}

Future<bool> applyStagedUpdate() async {
  if (!hasStagedUpdate()) return false;
  // A staged tree that has already had its turn is a failed swap, not a
  // pending one. Retrying it is what produced the loop.
  if (_swapAlreadyAttempted()) {
    _discardStagedUpdate();
    return false;
  }
  try {
    final script = await _writeSwapScript();
    // Written before launching, not after: if the swap works, this process is
    // gone and the marker goes with the old install anyway; if it does not,
    // the marker is what stops the next launch from trying again.
    await _attemptMarker.writeAsString(DateTime.now().toIso8601String());
    await _launchDetached(script);
    // The script waits for this process to go away before touching anything.
    exit(0);
  } catch (_) {
    _discardStagedUpdate();
    return false;
  }
}

/// Runs the swap script without putting a window on screen.
///
/// On Windows `Process.start('cmd', …)` opens a console — on Windows 11 that
/// surfaces as a Terminal window, which reads as the app spawning a shell at
/// you. Dart's `Process.start` has no flag to suppress it, so the script is
/// launched through `wscript` running a two-line VBScript, which is the
/// dependency-free way to start something genuinely hidden.
Future<void> _launchDetached(File script) async {
  if (!Platform.isWindows) {
    await Process.start('sh', [script.path], mode: ProcessStartMode.detached);
    return;
  }
  final launcher = File('${script.parent.path}\\shift_ai_update_launch.vbs');
  // `Run(cmd, 0, False)`: window style 0 is hidden, and False means do not
  // wait — the script has its own wait-for-exit loop.
  await launcher.writeAsString(
      'CreateObject("WScript.Shell").Run "" & Chr(34) & "${script.path}"'
      ' & Chr(34), 0, False\r\n');
  await Process.start(
    'wscript',
    ['//B', '//Nologo', launcher.path],
    mode: ProcessStartMode.detached,
  );
}

/// The swap itself, as a detached script — the running process cannot
/// replace the directory it is executing from.
Future<File> _writeSwapScript() async {
  final dir = await getTemporaryDirectory();
  final install = _installDir.path;
  final staged = _stagedDir.path;
  final backup = '${install}_backup';
  final incoming = '${install}_incoming';
  final exe = '$install${Platform.pathSeparator}$_executableName';
  // Cleared by the script itself once the swap is decided, either way. Left
  // behind, it would block the *next* real update from ever being applied.
  final marker = _attemptMarker.path;

  if (Platform.isWindows) {
    final file = File('${dir.path}\\shift_ai_update.cmd');
    await file.writeAsString('''
@echo off
:wait
tasklist /FI "PID eq $pid" 2>nul | find "$pid" >nul
if not errorlevel 1 (
  timeout /t 1 /nobreak >nul
  goto wait
)
if exist "$backup" rmdir /s /q "$backup"
if exist "$incoming" rmdir /s /q "$incoming"
move "$staged" "$incoming" >nul || goto failed
move "$install" "$backup" >nul || goto failed
move "$incoming" "$install" >nul || move "$backup" "$install" >nul
if exist "$backup" rmdir /s /q "$backup"
rem Relaunch from inside the new install; the old working directory is gone.
cd /d "$install"
start "" "$exe"
goto done

:failed
rem Leave nothing staged. A staged tree that survives a failed swap is what
rem made the app quit, flash a console and come back unchanged on every
rem single launch. The next check downloads it again.
if exist "$incoming" rmdir /s /q "$incoming"
if exist "$staged" rmdir /s /q "$staged"
start "" "$exe"

:done
if exist "$marker" del /q "$marker"
del "%~f0"
''');
    return file;
  }

  final file = File('${dir.path}/shift_ai_update.sh');
  await file.writeAsString('''
#!/bin/sh
# Wait for the app to exit; it cannot replace the directory it runs from.
while kill -0 $pid 2>/dev/null; do sleep 0.2; done

# Leave nothing staged whichever way this goes: a staged tree that survives a
# failed swap makes every later launch quit and retry it, forever.
give_up() {
  rm -rf "$incoming" "$staged"
  rm -f "$marker"
  "$exe" >/dev/null 2>&1 &
  exit 1
}

rm -rf "$backup" "$incoming"
# Rename into place in two steps so a failure leaves the old install
# recoverable. Nothing is deleted until the new tree is live.
mv "$staged" "$incoming" || give_up
mv "$install" "$backup" || give_up
if ! mv "$incoming" "$install"; then
  mv "$backup" "$install"
  give_up
fi
rm -rf "$backup"
rm -f "$marker"

# Relaunch from inside the new install. The old working directory was just
# renamed out from under this script, and a process whose cwd no longer
# exists starts unreliably — measured: the relaunched window never mapped.
cd "$install" || exit 1
"$exe" >/dev/null 2>&1 &
rm -f "\$0"
''');
  await Process.run('chmod', ['+x', file.path]);
  return file;
}
