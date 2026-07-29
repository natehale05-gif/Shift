import 'package:http/http.dart' as http;

import 'asset_for_platform.dart';
import 'update_check.dart';
import 'update_installer.dart' show InstallOutcome;

/// Web needs no updater. `web/index.html` registers a `controllerchange`
/// listener that reloads the page as soon as a new service worker takes
/// control, so a browser tab picks up each deploy on its own — downloading a
/// desktop installer into it would be nonsense.
InstallMode installMode() => InstallMode.unsupported;

bool hasStagedUpdate() => false;

bool canReplaceInPlace() => false;

Future<InstallOutcome> downloadAndInstall(
  ReleaseAsset asset, {
  void Function(double progress)? onProgress,
  http.Client Function()? clientFactory,
}) async =>
    InstallOutcome.failed;

Future<bool> applyStagedUpdate() async => false;
