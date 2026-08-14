import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'artifact.dart';
import 'kv_store.dart';

/// The deliverables a conversation produced, kept between launches.
///
/// One key per conversation rather than one per artifact: a conversation's
/// artifacts are always read together — the panel needs the whole set to offer
/// "the previous one" — and a page is a few kilobytes, so the read that saves
/// nothing costs nothing either.
///
/// On the same [KvStore] as the chats, with the same honest caveat their store
/// carries: this is the wrong store for documents and the right *next* one. The
/// line at which it gets replaced is attachments, which are bytes rather than
/// text.
class ArtifactStore extends ChangeNotifier {
  static const _prefix = 'artifacts.';

  final KvStore _kv;

  /// Cached per conversation, because the panel rebuilds on every keystroke of
  /// a streaming reply and decoding a page each time would be visible.
  final Map<String, List<Artifact>> _byConversation = {};

  ArtifactStore(this._kv);

  Future<void> load() async {
    await _kv.load();
    // The cache is dropped, so this is a *reload*. Without it a store whose
    // underlying data was cleared keeps answering from memory — which is how
    // "delete everything" left the pages on screen.
    _byConversation.clear();
  }

  /// Everything made in [conversationId], oldest first.
  List<Artifact> forConversation(String conversationId) {
    final cached = _byConversation[conversationId];
    if (cached != null) return List.unmodifiable(cached);

    final raw = _kv.get('$_prefix$conversationId');
    if (raw == null) return const [];

    List<Artifact> parsed;
    try {
      final decoded = jsonDecode(raw);
      parsed = [
        for (final entry in decoded is List ? decoded : const [])
          ?Artifact.fromJson(entry),
      ];
    } catch (_) {
      // A corrupt row costs its artifacts, not the conversation they belong
      // to — the transcript is stored separately and is still readable.
      parsed = const [];
    }

    _byConversation[conversationId] = parsed;
    return List.unmodifiable(parsed);
  }

  /// Adds a new artifact, or replaces one with the same id.
  ///
  /// Replacing by id is what makes a revision a new *version* of the thing on
  /// screen rather than a second near-identical entry beside it.
  Future<void> save(Artifact artifact) async {
    final id = artifact.conversationId;
    final current = [...forConversation(id)];
    final at = current.indexWhere((a) => a.id == artifact.id);
    if (at >= 0) {
      current[at] = artifact;
    } else {
      current.add(artifact);
    }

    _byConversation[id] = current;
    await _kv.put(
      '$_prefix$id',
      jsonEncode([for (final a in current) a.toJson()]),
    );
    notifyListeners();
  }

  Future<void> removeConversation(String conversationId) async {
    _byConversation.remove(conversationId);
    await _kv.remove('$_prefix$conversationId');
    notifyListeners();
  }
}
