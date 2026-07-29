import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/writing_style.dart';
import '../persistence/persistence_service.dart';

const _uuid = Uuid();

/// The built-in response styles (Claude's Normal/Concise/Explanatory/Formal),
/// id → display label. The prompt clauses for these live in
/// `assembleSystemPrompt`; custom styles carry their own instruction text.
const Map<String, String> builtInStyles = {
  'normal': 'Normal',
  'concise': 'Concise',
  'explanatory': 'Explanatory',
  'formal': 'Formal',
};

bool isBuiltInStyle(String id) => builtInStyles.containsKey(id);

/// Owns the user's custom writing styles (create/edit/delete), persisted to
/// IndexedDB. Built-in styles are not stored here.
class StylesStore extends ChangeNotifier {
  final PersistenceService persistence;

  List<WritingStyle> _styles = [];

  StylesStore({required this.persistence});

  List<WritingStyle> get customStyles => List.unmodifiable(_styles);

  WritingStyle? styleById(String? id) {
    if (id == null) return null;
    for (final s in _styles) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Display label for any style id (built-in or custom); null if unknown.
  String? labelFor(String id) => builtInStyles[id] ?? styleById(id)?.name;

  Future<void> load() async {
    _styles = (await persistence.loadCustomStyles())
        .map((e) => WritingStyle.fromJson(e as Map<String, dynamic>))
        .toList();
    notifyListeners();
  }

  WritingStyle create(String name, String instructions) {
    final style = WritingStyle(
      id: _uuid.v4(),
      name: name.trim(),
      instructions: instructions.trim(),
    );
    _styles.add(style);
    notifyListeners();
    _persist();
    return style;
  }

  void update(String id, {String? name, String? instructions}) {
    _styles = [
      for (final s in _styles)
        s.id == id ? s.copyWith(name: name, instructions: instructions) : s,
    ];
    notifyListeners();
    _persist();
  }

  void remove(String id) {
    _styles.removeWhere((s) => s.id == id);
    notifyListeners();
    _persist();
  }

  Future<void> _persist() =>
      persistence.saveCustomStyles(_styles.map((s) => s.toJson()).toList());
}
