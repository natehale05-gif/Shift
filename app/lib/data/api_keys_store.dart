import 'package:flutter/foundation.dart';

import 'kv_store.dart';

/// The provider keys this device holds.
///
/// Two rules here are not style, they are field reports from v1 where each one
/// cost somebody a session:
///
/// 1. **All whitespace is stripped, not `trim()`ed.** A key copied out of a
///    dashboard or an email frequently arrives with a line break *in the
///    middle*. `trim()` cleans the ends and leaves that, the key goes out as
///    `x-api-key` with a newline in it, the provider answers 401, and the app
///    then says "double-check your key" — pointing at the one thing that was
///    fine.
/// 2. **It is stripped on load as well as on save.** Without that, a key saved
///    by an earlier build keeps whatever was pasted, and the fix never reaches
///    the people already affected by it.
class ApiKeysStore extends ChangeNotifier {
  static const _prefix = 'key.';

  final KvStore _kv;
  final Map<String, String> _keys = {};

  ApiKeysStore(this._kv);

  Future<void> load() async {
    await _kv.load();
    // Same reason as the sibling stores: a reload has to forget, or a key
    // removed underneath this store stays usable for the rest of the session.
    _keys.clear();
    for (final name in _kv.keys()) {
      if (!name.startsWith(_prefix)) continue;
      final value = _kv.get(name);
      if (value == null) continue;
      final clean = _clean(value);
      if (clean.isEmpty) continue;
      _keys[name.substring(_prefix.length)] = clean;
      // Rewritten so the repair is permanent rather than re-applied on every
      // launch, and so anything else reading the store sees the clean value.
      if (clean != value) await _kv.put(name, clean);
    }
    notifyListeners();
  }

  /// Every whitespace character, anywhere. No provider key contains one.
  static String _clean(String raw) => raw.replaceAll(RegExp(r'\s'), '');

  bool has(String providerId) => _keys.containsKey(providerId);

  String? get(String providerId) => _keys[providerId];

  /// What to show instead of the key: enough to recognise it, not enough to
  /// use it. A full key on screen is a key in a screenshot.
  String? masked(String providerId) {
    final key = _keys[providerId];
    if (key == null) return null;
    final tail = key.length <= 4 ? key : key.substring(key.length - 4);
    return '••••••••$tail';
  }

  Set<String> get keyed => _keys.keys.toSet();

  Future<void> set(String providerId, String raw) async {
    final clean = _clean(raw);
    if (clean.isEmpty) return remove(providerId);
    _keys[providerId] = clean;
    await _kv.put('$_prefix$providerId', clean);
    notifyListeners();
  }

  Future<void> remove(String providerId) async {
    _keys.remove(providerId);
    await _kv.remove('$_prefix$providerId');
    notifyListeners();
  }
}
