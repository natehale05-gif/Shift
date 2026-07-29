import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/persistence/storage/idb_factory_io.dart';
import 'package:shift_ai/data/persistence/storage/storage_backend.dart';

/// The regression these cover: off-web storage used to be
/// `newIdbFactoryMemory()`, so a downloaded desktop or Android app forgot
/// every chat, project and API key the moment it closed.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('shift_storage_test');
  });

  tearDown(() async {
    // Back to the in-memory default so nothing later inherits the temp root.
    resetPersistentStorage();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('without a configured root, storage stays in-memory and isolated',
      () async {
    // What `flutter test` relies on: each backend gets its own memory factory,
    // so tests never see each other's data.
    await StorageBackend().putConversationJson('c1', '{"id":"c1"}');
    final other = await StorageBackend().getAllConversationJson();

    expect(other, isEmpty);
  });

  test('conversations survive a restart once a root is configured', () async {
    usePersistentStorage(tempDir.path);

    final first = StorageBackend();
    await first.putConversationJson('c1', '{"id":"c1","title":"Bakery"}');
    await first.putKv('shift_ai.anthropic_key.v1', 'sk-test');

    // A brand-new backend over the same root is what a relaunch looks like.
    final afterRestart = StorageBackend();
    final conversations = await afterRestart.getAllConversationJson();
    final key = await afterRestart.getKv('shift_ai.anthropic_key.v1');

    expect(conversations, contains('{"id":"c1","title":"Bakery"}'));
    expect(key, 'sk-test');
  });

  test('assets survive a restart too', () async {
    usePersistentStorage(tempDir.path);
    final bytes = Uint8List.fromList([1, 2, 3, 4, 5]);

    await StorageBackend().putAsset('a1', bytes);
    final read = await StorageBackend().getAsset('a1');

    expect(read, bytes);
  });

  test('a configured root actually writes to disk', () async {
    usePersistentStorage(tempDir.path);
    await StorageBackend().putConversationJson('c1', '{"id":"c1"}');

    final written = tempDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.lengthSync() > 0)
        .toList();
    expect(written, isNotEmpty,
        reason: 'sembast should have written a database file');
  });
}
