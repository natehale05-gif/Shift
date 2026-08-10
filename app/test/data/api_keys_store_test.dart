import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/kv_store.dart';

/// A real store on a real file in a temp directory, not a fake map — the
/// interesting behaviour here is what survives a restart, and a fake cannot
/// answer that.
void main() {
  late Directory dir;
  String path() => '${dir.path}/settings.json';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-keys');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<ApiKeysStore> open() async {
    final store = ApiKeysStore(KvStore(path: path()));
    await store.load();
    return store;
  }

  group('the store remembers', () {
    test('a key saved now is there after a restart', () async {
      final first = await open();
      await first.set('anthropic', 'sk-ant-abcd1234');

      final second = await open();
      expect(second.get('anthropic'), 'sk-ant-abcd1234');
      expect(second.has('anthropic'), isTrue);
    });

    test('a missing file opens empty rather than throwing', () async {
      final store = await open();
      expect(store.keyed, isEmpty);
    });

    test('a corrupt file opens empty rather than taking the app down',
        () async {
      await File(path()).writeAsString('{not json');
      final store = await open();
      expect(store.keyed, isEmpty);
    });

    test('removing leaves nothing behind on disk', () async {
      final first = await open();
      await first.set('anthropic', 'sk-ant-abcd1234');
      await first.remove('anthropic');

      expect(await File(path()).readAsString(), isNot(contains('sk-ant')));
      expect((await open()).has('anthropic'), isFalse);
    });
  });

  group('whitespace, which cost a user a session in v1', () {
    test('a key pasted with a line break in the middle is stored clean',
        () async {
      // The v1 defect exactly: `setKey` called `trim()`, which cleans the ends
      // and leaves a newline in the middle. The key went out as `x-api-key`
      // with a newline in it, the provider answered 401, and the app said
      // "double-check the key" — pointing at the one thing that was fine.
      final store = await open();
      await store.set('anthropic', 'sk-ant-abc\nd1234');

      expect(store.get('anthropic'), 'sk-ant-abcd1234');
      expect(store.get('anthropic'), isNot(contains('\n')));
    });

    test('spaces and tabs anywhere are stripped', () async {
      final store = await open();
      await store.set('openai', '  sk-proj \t abc123\r\n ');
      expect(store.get('openai'), 'sk-projabc123');
    });

    test('a key saved dirty by an earlier build reads back clean', () async {
      // The half of the fix that reaches people already affected. Cleaning
      // only on save leaves every key stored before the fix still broken, and
      // the user has no way to know they should re-paste it.
      await File(path())
          .writeAsString('{"key.anthropic":"sk-ant-abc\\nd1234"}');

      final store = await open();
      expect(store.get('anthropic'), 'sk-ant-abcd1234');

      // And repaired on disk, so it is fixed once rather than on every launch.
      expect(await File(path()).readAsString(), isNot(contains('\\n')));
    });

    test('a key that is only whitespace is treated as no key', () async {
      final store = await open();
      await store.set('anthropic', '   \n  ');
      expect(store.has('anthropic'), isFalse);
    });
  });

  group('what is shown', () {
    test('the mask keeps the last four and hides the rest', () async {
      final store = await open();
      await store.set('anthropic', 'sk-ant-secret-value-9876');

      final masked = store.masked('anthropic')!;
      expect(masked, endsWith('9876'));
      expect(masked, isNot(contains('secret')));
    });

    test('no key masks to null rather than to dots', () async {
      final store = await open();
      expect(store.masked('anthropic'), isNull);
    });
  });
}
