import 'package:http/http.dart' as http;

import 'asset_for_platform.dart';
import 'update_check.dart';
import 'update_installer_io.dart'
    if (dart.library.js_interop) 'update_installer_web.dart' as target;

export 'asset_for_platform.dart' show InstallMode;

/// What happened when the updater tried to apply a release.
enum InstallOutcome {
  /// Downloaded and unpacked beside the current install. It is applied on
  /// the next launch, or immediately via [applyStagedUpdate].
  staged,

  /// Downloaded and handed to the OS installer — the user finishes it there.
  /// macOS only.
  handedOff,

  /// Nothing was downloaded: the release page was opened instead, because this
  /// platform's own install flow is the only one it may use. Android only, and
  /// deliberately — see [InstallMode.handOffToPage].
  ///
  /// Its own outcome rather than [handedOff] because the sentence a person
  /// reads has to differ: one says "drag it across", the other says "download
  /// it and tap it".
  openedPage,

  /// This copy cannot replace itself: it lives somewhere the user cannot
  /// write, such as a `.deb` installed under `/opt` or a Windows all-users
  /// install under `Program Files`. Nothing was downloaded. The update is
  /// real and the release page is the way to get it.
  notPermitted,

  /// Nothing was changed. The download failed, was short, or the unpacked
  /// tree did not look like an install.
  failed,
}

/// How this platform installs an update, if it can.
InstallMode get installMode => target.installMode();

/// Fetches [asset] and either stages it, hands it to the OS, or — on Android —
/// opens the release page without downloading anything.
///
/// Progress runs 0..1 across the download; unpacking is fast enough not to
/// report separately.
/// [pageUrl] is the release page. It is required rather than optional because
/// on Android it is the *only* thing used — nothing is downloaded there, and a
/// caller that forgot it would silently do nothing on one platform out of four.
Future<InstallOutcome> downloadAndInstall(
  ReleaseAsset asset, {
  required String pageUrl,
  void Function(double progress)? onProgress,
  http.Client Function()? clientFactory,
}) =>
    target.downloadAndInstall(
      asset,
      pageUrl: pageUrl,
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

/// Whether this copy can replace itself where it stands. False for a
/// system-wide install (`/opt` from a `.deb`, `Program Files`), which the app
/// cannot write to — the release page is the route for those.
bool get canReplaceInPlace => target.canReplaceInPlace();
