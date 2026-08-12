import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'kv_store.dart';
import 'note.dart';

/// Notes, kept between launches.
///
/// The same shape as [ConversationStore] — one index plus a body per note —
/// and for the same reason: the list is drawn when the mode opens, and reading
/// every note to draw a list of titles is work a phone does not need to do.
///
/// Same honest caveat too: [KvStore] is the wrong store for documents and the
/// right *next* one. The line at which it gets replaced is attachments, which
/// are bytes rather than text.
class NoteStore extends ChangeNotifier {
  static const _indexKey = 'notes.index';
  static const _bodyPrefix = 'note.';

  final KvStore _kv;
  List<NoteSummary> _index = [];

  NoteStore(this._kv);

  /// Newest first, which is the order a list of notes is read in.
  List<NoteSummary> get index => List.unmodifiable(_index);

  Future<void> load() async {
    await _kv.load();
    _index = _decodeIndex();
    notifyListeners();
  }

  List<NoteSummary> _decodeIndex() {
    final raw = _kv.get(_indexKey);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      return [
        for (final entry in decoded is List ? decoded : const [])
          ?NoteSummary.fromJson(entry),
      ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (_) {
      // A corrupt index costs the list, not the notes: the bodies are still
      // under their own keys and a note saved again puts its row back.
      return [];
    }
  }

  String body(String id) => _kv.get('$_bodyPrefix$id') ?? '';

  /// Writes [body] under [id], deriving the title and preview from it.
  ///
  /// Derived rather than passed in because notes are dictated: nobody types a
  /// title first, and a list of notes all called "Untitled" is a list you
  /// cannot use.
  Future<void> save(String id, String body) async {
    // The list is updated and announced **before** the disk write, not after.
    // A row appearing only once the file has landed means the list lags a note
    // someone just wrote — and it made the write's timing part of what the UI
    // shows, which is a race dressed up as an ordering.
    _index = [
      for (final note in _index)
        if (note.id != id) note,
      NoteSummary(
        id: id,
        title: noteTitleFrom(body),
        updatedAt: DateTime.now(),
        preview: notePreviewFrom(body),
      ),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    notifyListeners();

    await _kv.put('$_bodyPrefix$id', body);
    await _writeIndex();
  }

  Future<void> remove(String id) async {
    _index = [for (final note in _index) if (note.id != id) note];
    notifyListeners();
    await _kv.remove('$_bodyPrefix$id');
    await _writeIndex();
  }

  Future<void> _writeIndex() =>
      _kv.put(_indexKey, jsonEncode([for (final n in _index) n.toJson()]));
}
