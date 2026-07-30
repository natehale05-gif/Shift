import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/writing_style.dart';
import '../persistence/persistence_service.dart';

const _uuid = Uuid();

/// The built-in response styles — Claude's Normal/Concise/Explanatory/Formal.
///
/// They are [WritingStyle]s like any other, because they *are* the same thing:
/// a name and the instructions folded into the system prompt when the style is
/// active. Built-ins used to be a separate id→label map with their instruction
/// text living in `assembleSystemPrompt`, which meant one concept had two
/// shapes, two lookup paths, and a preference string that had to be split back
/// apart at the point of use to tell them apart.
///
/// Normal carries no instructions on purpose: it is the absence of a style, not
/// a style that asks for plainness.
const List<WritingStyle> builtInStyles = [
  WritingStyle(id: 'normal', name: 'Normal', instructions: ''),
  WritingStyle(
    id: 'concise',
    name: 'Concise',
    instructions: 'keep responses short and direct — lead with the answer, '
        'minimal preamble.',
  ),
  WritingStyle(
    id: 'explanatory',
    name: 'Explanatory',
    instructions: 'give thorough, well-structured responses that teach — '
        'explain the reasoning and include helpful examples.',
  ),
  WritingStyle(
    id: 'formal',
    name: 'Formal',
    instructions: 'write in a polished, professional register — complete '
        'sentences, no slang or emoji.',
  ),
];

bool isBuiltInStyle(String id) => builtInStyles.any((s) => s.id == id);

/// Owns the user's custom writing styles (create/edit/delete), persisted to
/// IndexedDB. Built-in styles are const, so only custom ones are stored.
class StylesStore extends ChangeNotifier {
  final PersistenceService persistence;

  List<WritingStyle> _styles = [];

  StylesStore({required this.persistence});

  List<WritingStyle> get customStyles => List.unmodifiable(_styles);

  /// Every style the user can pick, built-ins first — the list the Settings
  /// picker renders and the order it renders them in.
  List<WritingStyle> get allStyles => [...builtInStyles, ..._styles];

  /// Resolves an id to its style, built-in or custom, or null when nothing
  /// answers to it — which is what a style deleted while selected leaves
  /// behind, and it degrades to Normal rather than breaking.
  WritingStyle? styleById(String? id) {
    if (id == null) return null;
    for (final s in allStyles) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Display label for any style id (built-in or custom); null if unknown.
  String? labelFor(String id) => styleById(id)?.name;

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
