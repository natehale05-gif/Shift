import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/update/asset_for_platform.dart';
import '../../core/update/release_version.dart';
import '../../core/update/update_check.dart';
import '../../core/update/update_installer.dart';
import '../persistence/persistence_service.dart';

enum UpdateStatus {
  /// Nothing has been checked yet this launch.
  idle,
  checking,
  upToDate,

  /// A newer release exists but has not been fetched — either automatic
  /// installs are off, or this platform has nothing to fetch.
  available,

  /// Fetching it now. [UpdateStore.progress] runs 0..1.
  downloading,

  /// Unpacked beside the install and applied on the next launch, or now via
  /// [UpdateStore.restartAndUpdate]. Linux and Windows.
  readyToRestart,

  /// Handed to the OS installer; the user finishes there. macOS and Android,
  /// where unsigned software cannot install silently.
  handedOff,

  /// The check or the download could not complete — offline, rate-limited,
  /// or no release published yet. Deliberately distinct from [upToDate]: the
  /// app must not claim to be current when it does not know.
  failed,
}

/// Tracks whether the running build is the newest published one.
///
/// Web builds never check: the service worker in `web/index.html` already
/// swaps in a new deploy on its own, so there is nothing here for a browser
/// tab to tell the user.
class UpdateStore extends ChangeNotifier {
  final PersistenceService persistence;
  final UpdateCheck _check;

  /// How long an automatic check stays good for. The manual button ignores it.
  static const checkInterval = Duration(hours: 24);

  UpdateStatus _status = UpdateStatus.idle;
  ReleaseInfo? _latest;
  String _currentVersion = '';
  String? _dismissedTag;
  DateTime? _checkedAt;
  bool _autoInstall = true;
  double _progress = 0;

  UpdateStore({
    required this.persistence,
    UpdateCheck? check,
  }) : _check = check ?? UpdateCheck();

  UpdateStatus get status => _status;
  ReleaseInfo? get latest => _latest;

  /// Download progress, 0..1, while [status] is [UpdateStatus.downloading].
  double get progress => _progress;

  /// Whether to fetch and stage a new release without being asked.
  ///
  /// An app that rewrites its own install directory needs a way to say no,
  /// so this is a real preference rather than a constant. Off still checks
  /// and still reports — it just stops at [UpdateStatus.available].
  bool get autoInstall => _autoInstall;

  /// How this platform applies an update, if it can.
  InstallMode get mode => installMode;

  /// The running build's version, e.g. `0.1.0`. Empty until [load] runs.
  String get currentVersion => _currentVersion;

  /// Whether this platform has anything to check at all.
  bool get enabled => !kIsWeb;

  /// Whether to show the strip above the shell. A staged update always shows
  /// — it is one click from done and dismissing it would be dismissing work
  /// already downloaded — while a merely-available one respects dismissal.
  bool get shouldPrompt {
    if (_latest == null) return false;
    return switch (_status) {
      UpdateStatus.readyToRestart || UpdateStatus.handedOff => true,
      UpdateStatus.downloading => true,
      UpdateStatus.available => _latest!.tag != _dismissedTag,
      _ => false,
    };
  }

  Future<void> load() async {
    if (!enabled) return;
    try {
      final info = await PackageInfo.fromPlatform();
      _currentVersion = info.version;
    } catch (_) {
      // A platform without a packaged manifest leaves this empty, which
      // `isNewerRelease` treats as unparseable — so no update is offered
      // rather than a wrong one.
      _currentVersion = '';
    }

    final state = await persistence.loadUpdateState();
    _dismissedTag = state['dismissed'] as String?;
    _autoInstall = state['auto'] as bool? ?? true;
    final checkedAt = state['checkedAt'];
    if (checkedAt is String) _checkedAt = DateTime.tryParse(checkedAt);

    notifyListeners();
  }

  Future<void> setAutoInstall(bool value) async {
    _autoInstall = value;
    await _persist();
    notifyListeners();
  }

  /// The launch-time check. Does nothing if one ran within [checkInterval],
  /// so opening the app ten times in a day costs one request.
  Future<void> checkIfDue() async {
    if (!enabled) return;
    final last = _checkedAt;
    if (last != null && DateTime.now().difference(last) < checkInterval) return;
    await checkNow();
  }

  /// An explicit check, from the Settings button.
  Future<void> checkNow() async {
    if (!enabled || _status == UpdateStatus.checking) return;

    _status = UpdateStatus.checking;
    notifyListeners();

    final release = await _check.fetchLatest();
    _checkedAt = DateTime.now();

    if (release == null) {
      _status = UpdateStatus.failed;
      await _persist();
      notifyListeners();
      return;
    }

    _latest = release;
    if (!isNewerRelease(_currentVersion, release.tag)) {
      _status = UpdateStatus.upToDate;
      await _persist();
      notifyListeners();
      return;
    }

    _status = UpdateStatus.available;
    await _persist();
    notifyListeners();

    if (_autoInstall && mode != InstallMode.unsupported) await install();
  }

  /// Fetches the release and either stages it or opens the OS installer.
  ///
  /// Staging deliberately does **not** restart on its own: the app quitting
  /// mid-sentence to update itself would cost the user more than the update
  /// is worth. The swap runs on the next launch, or when they press restart.
  Future<void> install() async {
    final release = _latest;
    if (release == null || _status == UpdateStatus.downloading) return;

    final asset = assetForPlatform(release.assets, _platformName);
    if (asset == null) {
      // A release with nothing for this platform is not a failure to report
      // as one -- the download buttons are still there.
      _status = UpdateStatus.available;
      notifyListeners();
      return;
    }

    _status = UpdateStatus.downloading;
    _progress = 0;
    notifyListeners();

    final outcome = await downloadAndInstall(asset, onProgress: (p) {
      _progress = p.clamp(0.0, 1.0);
      notifyListeners();
    });

    _status = switch (outcome) {
      InstallOutcome.staged => UpdateStatus.readyToRestart,
      InstallOutcome.handedOff => UpdateStatus.handedOff,
      InstallOutcome.failed => UpdateStatus.failed,
    };
    notifyListeners();
  }

  /// Applies a staged update now. Does not return on success — the process
  /// is replaced by the new one.
  Future<void> restartAndUpdate() => applyStagedUpdate();

  /// Hides the strip for this version only — the next release prompts again.
  Future<void> dismiss() async {
    final tag = _latest?.tag;
    if (tag == null) return;
    _dismissedTag = tag;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() => persistence.saveUpdateState({
        if (_checkedAt != null) 'checkedAt': _checkedAt!.toIso8601String(),
        if (_dismissedTag != null) 'dismissed': _dismissedTag,
        'auto': _autoInstall,
      });

  /// The same string `Platform.operatingSystem` would give — `linux`,
  /// `windows`, `macos`, `android` — without importing `dart:io` into a file
  /// the web build also compiles. `TargetPlatform.macOS` needs the
  /// lower-casing; the others are already lower.
  String get _platformName =>
      kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();
}
