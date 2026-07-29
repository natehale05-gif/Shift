import 'update_check.dart';

/// The release asset that can install onto [platform], or null if the
/// release carries nothing for it.
///
/// Matched by **suffix**, not by the exact filename `release.yml` happens to
/// produce today. If an asset is renamed the worst case is "no update found"
/// rather than downloading a `.dmg` onto an Android phone — the failure that
/// matters here is the wrong file, not the missing one.
///
/// [platform] is `Platform.operatingSystem`: `linux`, `windows`, `macos`,
/// `android`. Anything else (including `ios`, which this project does not
/// package) returns null.
ReleaseAsset? assetForPlatform(List<ReleaseAsset> assets, String platform) {
  final suffixes = _suffixes[platform];
  if (suffixes == null) return null;

  for (final suffix in suffixes) {
    for (final asset in assets) {
      if (asset.name.toLowerCase().endsWith(suffix)) return asset;
    }
  }
  return null;
}

/// Accepted endings per platform, most specific first. `.tar.gz` is listed
/// ahead of `.tgz` and `.zip` so a release carrying both hands Linux the
/// bundle the workflow actually builds.
const _suffixes = <String, List<String>>{
  'linux': ['.tar.gz', '.tgz'],
  'windows': ['.zip'],
  'macos': ['.dmg'],
  'android': ['.apk'],
};

/// Whether a platform can install without the user confirming anything.
///
/// Linux and Windows ship as a self-contained directory that the app can
/// swap and relaunch. macOS and Android cannot: replacing an *unsigned*
/// `.app` still re-triggers Gatekeeper, and Android has no silent sideload
/// path at all — both hand the file to the OS and the user confirms once.
/// This is OS policy for unsigned software, not a shortcut taken here.
InstallMode installModeFor(String platform) => switch (platform) {
      'linux' || 'windows' => InstallMode.replaceAndRelaunch,
      'macos' || 'android' => InstallMode.handOffToSystem,
      _ => InstallMode.unsupported,
    };

enum InstallMode {
  /// Swap the install directory and restart. No interaction.
  replaceAndRelaunch,

  /// Open the downloaded installer and let the OS take over.
  handOffToSystem,

  /// Nothing to do — the web build updates itself via its service worker.
  unsupported,
}
