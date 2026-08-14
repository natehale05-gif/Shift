import 'dart:convert';
import 'dart:io';

/// Off-web: one JSON file beside the executable's own data.
///
/// Read whole and written whole. That is fine at this size and would not be
/// for conversations, which is the line at which this gets replaced rather
/// than grown.
class KvStore {
  final String _path;
  Map<String, String> _values = {};

  KvStore({String? path})
      : _path = path ??
            '${Platform.environment['HOME'] ?? '.'}/.shift/settings.json';

  Future<void> load() async {
    try {
      final file = File(_path);
      if (!await file.exists()) return;
      final raw = jsonDecode(await file.readAsString());
      if (raw is Map) {
        _values = {
          for (final entry in raw.entries)
            if (entry.value is String) '${entry.key}': entry.value as String,
        };
      }
    } catch (_) {
      // A corrupt or unreadable file reads as empty. Throwing here would take
      // the app down on launch over a setting, which is a far worse trade than
      // losing one.
      _values = {};
    }
  }

  String? get(String key) => _values[key];

  Iterable<String> keys() => _values.keys;

  Future<void> put(String key, String value) async {
    _values[key] = value;
    await _flush();
  }

  Future<void> remove(String key) async {
    _values.remove(key);
    await _flush();
  }

  Future<void> _flush() async {
    try {
      final file = File(_path);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(_values));
    } catch (_) {
      // Held in memory for this session rather than surfacing a disk error
      // mid-typing. The next launch will not have it, which is the honest
      // consequence and not one worth interrupting anyone over.
    }
  }
}
