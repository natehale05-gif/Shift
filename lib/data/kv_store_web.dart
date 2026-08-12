import 'package:web/web.dart' as web;

/// The browser: `localStorage`, namespaced so two apps on the same origin — v1
/// at `/Shift/v1/` and v2 at `/Shift/` share one — cannot read or clobber each
/// other's values.
///
/// **What this means for a key, said plainly because the UI says it too:**
/// anything stored here is readable by script on this origin. It is the same
/// exposure every browser-based bring-your-own-key tool has, and it is the
/// honest argument for the managed path, where the key never leaves the
/// server. It is not a reason to pretend the storage is something it is not.
class KvStore {
  static const _prefix = 'shift.v2.';

  final Map<String, String> _values = {};

  KvStore({String? path});

  Future<void> load() async {
    final storage = web.window.localStorage;
    for (var i = 0; i < storage.length; i++) {
      final key = storage.key(i);
      if (key == null || !key.startsWith(_prefix)) continue;
      final value = storage.getItem(key);
      if (value != null) _values[key.substring(_prefix.length)] = value;
    }
  }

  String? get(String key) => _values[key];

  Iterable<String> keys() => _values.keys;

  Future<void> put(String key, String value) async {
    _values[key] = value;
    web.window.localStorage.setItem('$_prefix$key', value);
  }

  Future<void> remove(String key) async {
    _values.remove(key);
    web.window.localStorage.removeItem('$_prefix$key');
  }
}
