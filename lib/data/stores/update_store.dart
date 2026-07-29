import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/update/release_version.dart';
import '../../core/update/update_check.dart';
import '../persistence/persistence_service.dart';

enum UpdateStatus {
  /// Nothing has been checked yet this launch.
  idle,
  checking,
  upToDate,

  /// A newer release exists. E2 turns this into a download.
  available,

  /// The check could not complete — offline, rate-limited, or no release
  /// published yet. Deliberately distinct from [upToDate]: the app must not
  /// claim to be current when it does not know.
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

  UpdateStore({
    required this.persistence,
    UpdateCheck? check,
  }) : _check = check ?? UpdateCheck();

  UpdateStatus get status => _status;
  ReleaseInfo? get latest => _latest;

  /// The running build's version, e.g. `0.1.0`. Empty until [load] runs.
  String get currentVersion => _currentVersion;

  /// Whether this platform has anything to check at all.
  bool get enabled => !kIsWeb;

  /// Whether to show the "update available" strip: a newer release exists and
  /// the user has not dismissed this particular version.
  bool get shouldPrompt =>
      _status == UpdateStatus.available &&
      _latest != null &&
      _latest!.tag != _dismissedTag;

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
    final checkedAt = state['checkedAt'];
    if (checkedAt is String) _checkedAt = DateTime.tryParse(checkedAt);

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
    } else {
      _latest = release;
      _status = isNewerRelease(_currentVersion, release.tag)
          ? UpdateStatus.available
          : UpdateStatus.upToDate;
    }

    await _persist();
    notifyListeners();
  }

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
      });
}
