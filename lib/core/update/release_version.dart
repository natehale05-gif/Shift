/// Comparing the running build against a published release tag.
///
/// Pure on purpose. With auto-install on, this function decides whether the
/// app rewrites its own install directory, so it is the one piece of the
/// updater that has to be provable without a network, a filesystem or a fake.
library;

/// Whether [tag] names a release newer than the running [current] version.
///
/// [current] is a `pubspec` version as reported by the packaged manifest
/// (`0.1.0` or `0.1.0+1`); [tag] is a GitHub tag (`v0.1.1`). Both forms are
/// normalised before comparing:
///
/// * a leading `v` is dropped, so `v0.1.1` and `0.1.1` are the same release;
/// * the `+build` suffix is dropped — `0.1.0+1` **is** `0.1.0`, not a newer
///   one. Getting this wrong would have every downloaded copy reinstalling
///   the version it is already running, forever;
/// * segments compare numerically, so `0.10.0` beats `0.9.0`;
/// * a missing segment is zero, so `1.0` and `1.0.0` are equal.
///
/// Returns `false` for anything unparseable rather than guessing. An update
/// that does not happen is a nuisance; an update that should not have happened
/// replaces a working install.
bool isNewerRelease(String current, String tag) {
  final running = _parse(current);
  final candidate = _parse(tag);
  if (running == null || candidate == null) return false;

  final length = running.length > candidate.length ? running.length : candidate.length;
  for (var i = 0; i < length; i++) {
    final a = i < running.length ? running[i] : 0;
    final b = i < candidate.length ? candidate[i] : 0;
    if (b != a) return b > a;
  }
  return false;
}

/// The numeric segments of a version string, or null if it is not one.
List<int>? _parse(String raw) {
  var text = raw.trim();
  if (text.isEmpty) return null;
  if (text.startsWith('v') || text.startsWith('V')) text = text.substring(1);

  // Drop Flutter's build number (`+1`) and any pre-release suffix (`-beta.2`).
  // A pre-release is treated as its base version rather than ranked against
  // it: this project does not publish them, and inventing an ordering for
  // something untested is how a false positive gets in.
  final plus = text.indexOf('+');
  if (plus >= 0) text = text.substring(0, plus);
  final dash = text.indexOf('-');
  if (dash >= 0) text = text.substring(0, dash);

  if (text.isEmpty) return null;

  final segments = <int>[];
  for (final part in text.split('.')) {
    final value = int.tryParse(part);
    if (value == null || value < 0) return null;
    segments.add(value);
  }
  return segments;
}
