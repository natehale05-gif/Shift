import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// The browser: IndexedDB.
///
/// Not `localStorage`, which holds strings and caps an origin at roughly 5 MB
/// — three pictures. Not the Cache API, which is simpler to drive and is
/// explicitly evictable, so user-made images could vanish under disk pressure
/// with nothing to say about it. IndexedDB is the store the browser treats as
/// the user's data.
class AssetStore {
  static const _database = 'shift.v2.assets';
  static const _store = 'assets';

  web.IDBDatabase? _open;

  AssetStore({String? directory});

  /// Awaits an `IDBRequest`, which reports through events rather than a
  /// promise. Both handlers are attached before anything can fire, so a
  /// request that completes synchronously-fast is not missed.
  Future<JSAny?> _await(web.IDBRequest request) {
    final done = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      if (!done.isCompleted) done.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      if (!done.isCompleted) done.completeError(StateError('IndexedDB refused'));
    }).toJS;
    return done.future;
  }

  Future<web.IDBDatabase?> _db() async {
    final existing = _open;
    if (existing != null) return existing;
    try {
      final request = web.window.indexedDB.open(_database, 1);
      request.onupgradeneeded = ((web.Event _) {
        final db = request.result as web.IDBDatabase;
        if (!db.objectStoreNames.contains(_store)) db.createObjectStore(_store);
      }).toJS;
      final db = (await _await(request)) as web.IDBDatabase?;
      _open = db;
      return db;
    } catch (_) {
      // Private browsing modes and blocked storage both land here. The app
      // stays usable with images that do not survive a reload, which is worse
      // than persistence and much better than a launch that fails.
      return null;
    }
  }

  Future<T?> _run<T>(
    String mode,
    Future<T?> Function(web.IDBObjectStore store) work,
  ) async {
    final db = await _db();
    if (db == null) return null;
    try {
      final transaction = db.transaction(_store.toJS, mode);
      return await work(transaction.objectStore(_store));
    } catch (_) {
      return null;
    }
  }

  Future<void> put(String id, Uint8List bytes) async {
    await _run<bool>('readwrite', (store) async {
      await _await(store.put(bytes.toJS, id.toJS));
      return true;
    });
  }

  Future<Uint8List?> get(String id) => _run('readonly', (store) async {
        final value = await _await(store.get(id.toJS));
        if (value == null) return null;
        // Written as a typed array; read back as one. Anything else means
        // something other than this store wrote the record.
        return (value as JSUint8Array?)?.toDart;
      });

  Future<void> remove(String id) async {
    await _run<bool>('readwrite', (store) async {
      await _await(store.delete(id.toJS));
      return true;
    });
  }

  Future<List<String>> ids() async =>
      await _run('readonly', (store) async {
        final keys = await _await(store.getAllKeys());
        final list = (keys as JSArray<JSAny?>?)?.toDart ?? const [];
        return [
          for (final key in list)
            if (key.isA<JSString>()) (key as JSString).toDart,
        ];
      }) ??
      const [];

  Future<void> clear() async {
    for (final id in await ids()) {
      await remove(id);
    }
  }
}
