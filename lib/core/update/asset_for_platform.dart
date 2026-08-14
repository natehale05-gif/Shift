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
/// `android`. Anything else (including `ios`, which cannot be distributed this
/// way at all) returns null.
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

/// Accepted endings per platform, most specific first.
///
/// Linux and Windows each publish two: an installer people download once, and
/// a portable archive. The **portable one is what an update uses**, and that is
/// not a preference — a `.deb` installs into `/opt` and an all-users `.exe`
/// into `Program Files`, both root-owned, so neither can replace itself.
/// `canReplaceInPlace` detects that case before spending the bandwidth.
const _suffixes = <String, List<String>>{
  'linux': ['.tar.gz', '.tgz'],
  'windows': ['.zip'],
  'macos': ['.dmg'],
  'android': ['.apk'],
};

/// How far this platform can take an update on its own.
///
/// Linux and Windows ship as a self-contained directory the app can swap and
/// relaunch. The other two cannot, for reasons that are OS policy rather than
/// effort here:
///
/// * **macOS** — replacing an *unsigned* `.app` re-triggers Gatekeeper anyway,
///   so an in-place swap would trade one click for a scarier one. The `.dmg`
///   is downloaded and opened; the user drags it across once.
/// * **Android** — handing an APK to the package installer needs
///   `REQUEST_INSTALL_PACKAGES`, which Play's Device and Network Abuse policy
///   prohibits for an app like this one. It was in the app this rebuild
///   replaced, and it is one of the reasons there was a rebuild. So the app
///   says a new version exists and opens the release page; the download and
///   the install are Android's own, with its own confirmation.
///
/// Keeping that permission out is a decision with a guard on it:
/// `app.yml` fails the build if it appears in the manifest, and a test asserts
/// no code here names it.
InstallMode installModeFor(String platform) => switch (platform) {
      'linux' || 'windows' => InstallMode.replaceAndRelaunch,
      'macos' => InstallMode.handOffToSystem,
      'android' => InstallMode.handOffToPage,
      _ => InstallMode.unsupported,
    };

enum InstallMode {
  /// Swap the install directory and restart. No interaction.
  replaceAndRelaunch,

  /// Download the installer and open it. The OS takes over from there.
  handOffToSystem,

  /// Do not download anything — open the release page and let the platform's
  /// own install flow handle it.
  handOffToPage,

  /// Nothing to do. The web build is never cached, so a reload is already the
  /// newest version.
  unsupported,
}
