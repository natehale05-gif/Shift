import 'package:http/http.dart' as http;

import 'asset_for_platform.dart';
import 'update_check.dart';
import 'update_installer_io.dart'
    if (dart.library.html) 'update_installer_web.dart' as target;

export 'asset_for_platform.dart' show InstallMode;

/// What happened when the updater tried to apply a release.
enum InstallOutcome {
  /// Downloaded and unpacked beside the current install. It is applied on
  /// the next launch, or immediately via [applyStagedUpdate].
  staged,

  /// Handed to the OS installer — the user finishes it there. macOS and
  /// Android only.
  handedOff,

  /// Nothing was changed. The download failed, was short, or the unpacked
  /// tree did not look like an install.
  failed,
}

/// How this platform installs an update, if it can.
InstallMode get installMode => target.installMode();

/// Fetches [asset] and either stages it or hands it to the OS.
///
/// Progress runs 0..1 across the download; unpacking is fast enough not to
/// report separately.
Future<InstallOutcome> downloadAndInstall(
  ReleaseAsset asset, {
  void Function(double progress)? onProgress,
  http.Client Function()? clientFactory,
}) =>
    target.downloadAndInstall(
      asset,
      onProgress: onProgress,
      clientFactory: clientFactory,
    );

/// Swaps a staged update into place and relaunches.
///
/// Never returns on success — the process is replaced. Returns false when
/// there is nothing staged or the swap could not be started.
Future<bool> applyStagedUpdate() => target.applyStagedUpdate();

/// Whether an unpacked update is sitting beside the install, waiting.
bool get hasStagedUpdate => target.hasStagedUpdate();
