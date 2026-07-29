import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/memory_entry.dart';
import '../persistence/persistence_service.dart';

const _uuid = Uuid();

/// Owns what SHIFT AI remembers about the user across conversations. Entries
/// are injected into every turn's system prompt (when memory is on and the
/// entry is enabled) and managed from Settings.
class MemoryStore extends ChangeNotifier {
  final PersistenceService persistence;

  static const int maxEntries = 100;

  List<MemoryEntry> _entries = [];
  bool _enabled = true;

  MemoryStore({required this.persistence});

  bool get enabled => _enabled;
  List<MemoryEntry> get entries => List.unmodifiable(_entries);

  /// The fact strings that should go into the prompt right now.
  List<String> get activeTexts => _enabled
      ? [for (final e in _entries) if (e.enabled) e.text]
      : const [];

  Future<void> load() async {
    final blob = await persistence.loadMemory();
    _enabled = blob['enabled'] as bool? ?? true;
    _entries = (blob['entries'] as List<dynamic>? ?? const [])
        .map((e) => MemoryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    notifyListeners();
  }

  void setEnabled(bool value) {
    _enabled = value;
    notifyListeners();
    _persist();
  }

  /// Adds a fact unless an equivalent one already exists (case-insensitive).
  /// Returns true if it was actually added.
  bool addFact(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    final key = trimmed.toLowerCase();
    if (_entries.any((e) => e.text.toLowerCase() == key)) return false;
    _entries.insert(
      0,
      MemoryEntry(id: _uuid.v4(), text: trimmed, createdAt: DateTime.now()),
    );
    if (_entries.length > maxEntries) {
      _entries = _entries.sublist(0, maxEntries);
    }
    notifyListeners();
    _persist();
    return true;
  }

  void editEntry(String id, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _entries = [
      for (final e in _entries) e.id == id ? e.copyWith(text: trimmed) : e,
    ];
    notifyListeners();
    _persist();
  }

  void toggleEntry(String id) {
    _entries = [
      for (final e in _entries)
        e.id == id ? e.copyWith(enabled: !e.enabled) : e,
    ];
    notifyListeners();
    _persist();
  }

  void removeEntry(String id) {
    _entries.removeWhere((e) => e.id == id);
    notifyListeners();
    _persist();
  }

  void clearAll() {
    _entries = [];
    notifyListeners();
    _persist();
  }

  Future<void> _persist() => persistence.saveMemory({
        'enabled': _enabled,
        'entries': _entries.map((e) => e.toJson()).toList(),
      });
}
