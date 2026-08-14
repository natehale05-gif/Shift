import 'package:http/http.dart' as http;

import 'asset_for_platform.dart';
import 'update_check.dart';
import 'update_installer.dart' show InstallOutcome;

/// Web needs no updater, and for a simpler reason than the app this replaced
/// had: **this build registers no service worker at all** — `flutter_bootstrap.js`
/// passes no `serviceWorkerSettings` — so nothing is cached and a reload is
/// always the newest deploy. There is no stale copy to update, and downloading
/// a desktop installer into a browser tab would be nonsense.
InstallMode installMode() => InstallMode.unsupported;

bool hasStagedUpdate() => false;

bool canReplaceInPlace() => false;

Future<InstallOutcome> downloadAndInstall(
  ReleaseAsset asset, {
  required String pageUrl,
  void Function(double progress)? onProgress,
  http.Client Function()? clientFactory,
}) async =>
    InstallOutcome.failed;

Future<bool> applyStagedUpdate() async => false;
