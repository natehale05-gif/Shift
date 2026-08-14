import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'asset_store.dart';
import 'kv_store.dart';
import 'made_image.dart';

/// Every picture the app has made, newest first.
///
/// Split in two on purpose: the index is a short list of records in the
/// [KvStore], and the bytes are in the [AssetStore]. That split is what lets
/// the gallery open without decoding a hundred megabytes, and what stops an
/// unrelated setting change from rewriting every image to disk.
///
/// The two can disagree, and the direction matters. An index entry whose bytes
/// are missing shows as a broken tile — visible, and recoverable by deleting
/// it. Bytes with no index entry are invisible and unreachable, so [sweep]
/// removes them; that is the leak, and it is the one worth a pass.
class ImageStore extends ChangeNotifier {
  static const _indexKey = 'images.index';

  final KvStore _kv;
  final AssetStore _assets;

  List<MadeImage> _index = [];

  /// A few decoded images kept about, because a list of tiles asks for the
  /// same bytes on every rebuild and reading them from disk each time is
  /// visible as flicker.
  final Map<String, Uint8List> _recent = {};
  static const _recentLimit = 24;

  ImageStore(this._kv, this._assets);

  List<MadeImage> get index => List.unmodifiable(_index);

  Future<void> load() async {
    await _kv.load();
    // Cleared before the early return, not after: a store whose data was
    // erased must not keep answering from memory.
    _index = [];
    _recent.clear();
    _held.clear();

    final raw = _kv.get(_indexKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw);
      _index = [
        for (final entry in decoded is List ? decoded : const [])
          ?MadeImage.fromJson(entry),
      ];
    } catch (_) {
      _index = [];
    }
  }

  /// What is known about one picture, or null when nothing is.
  ///
  /// Null is the ordinary answer for an image made in a private chat: it was
  /// deliberately never recorded, and every caller has to be able to show the
  /// picture anyway rather than treating the missing record as an error.
  MadeImage? record(String id) {
    for (final image in _index) {
      if (image.id == id) return image;
    }
    return null;
  }

  /// Bytes already in memory, or null. Synchronous so a tile can draw without
  /// a `FutureBuilder` flashing empty on every rebuild.
  Uint8List? cached(String id) => _recent[id];

  Future<Uint8List?> bytes(String id) async {
    final held = _recent[id];
    if (held != null) return held;
    final loaded = await _assets.get(id);
    if (loaded != null) _remember(id, loaded);
    return loaded;
  }

  /// Keeps bytes for this session without writing them.
  ///
  /// A private chat still has to *show* the picture it made, and a transcript
  /// finds one by id — so the id has to resolve to something. This is that
  /// something, and it is gone when the app is.
  ///
  /// Exempt from the cache's eviction, because for these there is nowhere to
  /// read them back from: evicting one would blank a picture that is still on
  /// screen, with no way to recover it.
  void hold(String id, Uint8List bytes) {
    _held.add(id);
    _recent[id] = bytes;
  }

  final Set<String> _held = {};

  void _remember(String id, Uint8List bytes) {
    _recent[id] = bytes;
    if (_recent.length <= _recentLimit) return;
    for (final key in _recent.keys) {
      if (_held.contains(key) || key == id) continue;
      _recent.remove(key);
      return;
    }
  }

  /// Writes the bytes **before** the index that points at them.
  ///
  /// The order is the whole point: interrupted the other way round, the index
  /// names an image the app cannot show. This way an interruption leaves bytes
  /// nothing points at, which [sweep] cleans up and nobody ever sees.
  Future<void> save(MadeImage image, Uint8List bytes) async {
    await _assets.put(image.id, bytes);
    _remember(image.id, bytes);

    _index = [image, ..._index.where((i) => i.id != image.id)];
    await _flush();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    _index = [for (final image in _index) if (image.id != id) image];
    _recent.remove(id);
    _held.remove(id);
    await _flush();
    await _assets.remove(id);
    notifyListeners();
  }

  /// Removes every picture and every byte behind them.
  ///
  /// Here rather than in the caller because this store is the only thing that
  /// holds the asset store: exposing that so Settings could clear it would
  /// give a second owner to the one thing whose two halves must go together.
  Future<void> clearAll() async {
    await _assets.clear();
    _index = [];
    _recent.clear();
    _held.clear();
    await _kv.remove(_indexKey);
    notifyListeners();
  }

  /// The bytes and what kind of picture they are.
  ///
  /// One call rather than two, because a caller that fetched the bytes and
  /// then looked up the type separately would have to handle the two
  /// disagreeing — and every caller wants both.
  Future<({Uint8List bytes, String mimeType})?> sourceFor(String id) async {
    final data = await bytes(id);
    if (data == null) return null;
    return (bytes: data, mimeType: record(id)?.mimeType ?? 'image/png');
  }

  /// Deletes bytes no index entry points at.
  ///
  /// An image saved by a run that was interrupted between the two writes has
  /// no record, so nothing can ever show or delete it. Left alone it is a leak
  /// that only grows, and on the web it is spending a quota the user cannot
  /// see. Returns how many went, so a test can tell "swept" from "found
  /// nothing".
  Future<int> sweep() async {
    final known = {for (final image in _index) image.id};
    var removed = 0;
    for (final id in await _assets.ids()) {
      if (known.contains(id)) continue;
      await _assets.remove(id);
      removed++;
    }
    return removed;
  }

  Future<void> _flush() => _kv.put(
        _indexKey,
        jsonEncode([for (final image in _index) image.toJson()]),
      );
}
