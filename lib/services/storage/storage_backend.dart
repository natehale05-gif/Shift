import 'dart:convert';
import 'dart:typed_data';

import 'package:idb_shim/idb.dart';

import 'idb_factory_stub.dart' if (dart.library.html) 'idb_factory_web.dart';

/// IndexedDB-backed storage (via idb_shim): a `kv` store for small strings,
/// a `conversations` store with one record per conversation (so saving a
/// chat rewrites only that chat, not the whole history blob), and an
/// `assets` store for binary payloads like generated images.
///
/// On the VM test target the same code runs against idb_shim's in-memory
/// factory — no dart:html anywhere in this file.
class StorageBackend {
  static const _dbName = 'shift_ai';
  static const _kvStore = 'kv';
  static const _conversationsStore = 'conversations';
  static const _assetsStore = 'assets';

  final IdbFactory _factory;
  Database? _db;

  StorageBackend({IdbFactory? factory})
      : _factory = factory ?? defaultIdbFactory();

  Future<Database> _open() async {
    return _db ??= await _factory.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (event) {
        final db = event.database;
        db.createObjectStore(_kvStore);
        db.createObjectStore(_conversationsStore);
        db.createObjectStore(_assetsStore);
      },
    );
  }

  Future<T> _run<T>(
    String storeName,
    String mode,
    Future<T> Function(ObjectStore store) action,
  ) async {
    final db = await _open();
    final txn = db.transaction(storeName, mode);
    final result = await action(txn.objectStore(storeName));
    await txn.completed;
    return result;
  }

  // --- kv ---

  Future<String?> getKv(String key) => _run(
        _kvStore,
        idbModeReadOnly,
        (store) async => await store.getObject(key) as String?,
      );

  Future<void> putKv(String key, String value) => _run(
        _kvStore,
        idbModeReadWrite,
        (store) => store.put(value, key),
      );

  Future<void> deleteKv(String key) => _run(
        _kvStore,
        idbModeReadWrite,
        (store) => store.delete(key),
      );

  // --- conversations (one JSON string per record, keyed by id) ---

  Future<List<String>> getAllConversationJson() => _run(
        _conversationsStore,
        idbModeReadOnly,
        (store) async =>
            (await store.getAll()).map((e) => e as String).toList(),
      );

  Future<void> putConversationJson(String id, String json) => _run(
        _conversationsStore,
        idbModeReadWrite,
        (store) => store.put(json, id),
      );

  Future<void> deleteConversation(String id) => _run(
        _conversationsStore,
        idbModeReadWrite,
        (store) => store.delete(id),
      );

  Future<void> clearConversations() => _run(
        _conversationsStore,
        idbModeReadWrite,
        (store) => store.clear(),
      );

  // --- assets (bytes stored base64 so every idb_shim backend accepts them) ---

  Future<void> putAsset(String id, Uint8List bytes) => _run(
        _assetsStore,
        idbModeReadWrite,
        (store) => store.put(
          {
            'b64': base64Encode(bytes),
            'savedAt': DateTime.now().toIso8601String(),
          },
          id,
        ),
      );

  Future<Uint8List?> getAsset(String id) => _run(
        _assetsStore,
        idbModeReadOnly,
        (store) async {
          final record = await store.getObject(id);
          if (record is! Map) return null;
          final b64 = record['b64'] as String?;
          return b64 != null ? base64Decode(b64) : null;
        },
      );

  Future<void> deleteAsset(String id) => _run(
        _assetsStore,
        idbModeReadWrite,
        (store) => store.delete(id),
      );

  /// All asset ids with their savedAt timestamps, oldest first — the prune
  /// order.
  Future<List<(String, DateTime)>> assetIndex() => _run(
        _assetsStore,
        idbModeReadOnly,
        (store) async {
          final keys = await store.getAllKeys();
          final values = await store.getAll();
          final entries = <(String, DateTime)>[];
          for (var i = 0; i < keys.length && i < values.length; i++) {
            final record = values[i];
            final savedAt = record is Map
                ? DateTime.tryParse(record['savedAt'] as String? ?? '')
                : null;
            entries.add((
              keys[i] as String,
              savedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ));
          }
          entries.sort((a, b) => a.$2.compareTo(b.$2));
          return entries;
        },
      );
}
