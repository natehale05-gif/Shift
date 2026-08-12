import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'kv_store.dart';

/// One saved conversation, as the sidebar needs it.
class ConversationSummary {
  final String id;
  final String title;
  final DateTime updatedAt;

  const ConversationSummary({
    required this.id,
    required this.title,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
      };

  static ConversationSummary? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    final updated = DateTime.tryParse('${raw['updatedAt']}');
    if (id is! String || title is! String || updated == null) return null;
    return ConversationSummary(id: id, title: title, updatedAt: updated);
  }
}

/// Conversations, kept between launches.
///
/// On the same [KvStore] that holds the keys — a JSON blob per conversation
/// plus one index. That is honestly the wrong store for this and the right
/// *next* one: a document database is what projects and attachments will need,
/// and choosing its shape now, before either exists, would be choosing twice.
/// The seam is small enough to replace when the requirement is real.
///
/// The index is separate from the bodies so the sidebar can be drawn without
/// reading every transcript — which matters on a phone at the moment the app
/// opens, and costs nothing to get right now.
class ConversationStore extends ChangeNotifier {
  static const _indexKey = 'chats.index';
  static const _bodyPrefix = 'chat.';

  final KvStore _kv;
  List<ConversationSummary> _index = [];

  ConversationStore(this._kv);

  List<ConversationSummary> get index => List.unmodifiable(_index);

  Future<void> load() async {
    await _kv.load();
    final raw = _kv.get(_indexKey);
    // Cleared first, so this is a *reload* and not a merge. Returning early on
    // an empty store used to leave the previous list in memory, which meant
    // erasing everything left the sidebar showing conversations that were no
    // longer on disk — and the next write would have put them back.
    _index = [];
    if (raw == null) return;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return;
      // `?element` — an entry that will not parse is dropped rather than
      // failing the whole index. One unreadable row should cost that row.
      _index = [
        for (final entry in list) ?ConversationSummary.fromJson(entry),
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      // A corrupt index costs the list, not the app. The bodies are still on
      // disk under their own keys, so nothing is destroyed by starting over.
      _index = [];
    }
    notifyListeners();
  }

  /// The stored items for [id], or an empty list.
  List<dynamic> body(String id) {
    final raw = _kv.get('$_bodyPrefix$id');
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> save({
    required String id,
    required String title,
    required List<Map<String, dynamic>> items,
  }) async {
    await _kv.put('$_bodyPrefix$id', jsonEncode(items));

    _index
      ..removeWhere((s) => s.id == id)
      ..insert(
        0,
        ConversationSummary(
          id: id,
          title: title,
          updatedAt: DateTime.now(),
        ),
      );

    await _writeIndex();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    await _kv.remove('$_bodyPrefix$id');
    _index.removeWhere((s) => s.id == id);
    await _writeIndex();
    notifyListeners();
  }

  Future<void> _writeIndex() =>
      _kv.put(_indexKey, jsonEncode([for (final s in _index) s.toJson()]));
}
