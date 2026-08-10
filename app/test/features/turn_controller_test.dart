import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/shell/mode.dart';

/// Proves the key you paste in Settings is the key the turn uses.
///
/// Without this the two halves can both be correct and unconnected, which is
/// exactly the state the app was in before Settings existed: a working engine
/// and a working store, and no answer.
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-turn');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<ApiKeysStore> keysWith(Map<String, String> entries) async {
    final store = ApiKeysStore(KvStore(path: '${dir.path}/settings.json'));
    await store.load();
    for (final e in entries.entries) {
      await store.set(e.key, e.value);
    }
    return store;
  }

  _controlTests();

  test('with no key, the turn says what is missing and names Settings',
      () async {
    final turn = TurnController(keys: await keysWith({}));
    addTearDown(turn.dispose);

    await turn.send('hello', mode: AppMode.chat);

    final reply = turn.items.whereType<Reply>().single;
    expect(reply.failure, isNotNull);
    expect(reply.failure, contains('Settings'),
        reason: 'the remedy has to name a place that exists');
    expect(reply.text, isEmpty);
  });

  test('with a key present, the turn reaches the provider instead', () async {
    // The key is nonsense, so this fails at the provider rather than before
    // it — which is the whole point. The assertion is that the sentence is no
    // longer the "nothing is set up" one, because that is the difference
    // between wired and unwired.
    final turn = TurnController(
      keys: await keysWith({'anthropic': 'sk-ant-not-a-real-key'}),
    );
    addTearDown(turn.dispose);

    await turn.send('hello', mode: AppMode.chat);

    final reply = turn.items.whereType<Reply>().single;
    expect(reply.failure ?? '', isNot(contains('No provider is set up')),
        reason: 'a stored key must change which failure happens');
  });

  test('the user turn is in the transcript either way', () async {
    final turn = TurnController(keys: await keysWith({}));
    addTearDown(turn.dispose);

    await turn.send('  hello  ', mode: AppMode.chat);

    final said = turn.items.whereType<UserSaid>().single;
    expect(said.text, 'hello', reason: 'trimmed, so a stray space is not sent');
  });

  test('an empty message does nothing at all', () async {
    final turn = TurnController(keys: await keysWith({}));
    addTearDown(turn.dispose);

    await turn.send('   ', mode: AppMode.chat);
    expect(turn.items, isEmpty);
  });

  test('New chat empties the transcript', () async {
    final turn = TurnController(keys: await keysWith({}));
    addTearDown(turn.dispose);

    await turn.send('hello', mode: AppMode.chat);
    expect(turn.items, isNotEmpty);

    turn.clear();
    expect(turn.isEmpty, isTrue);
  });
}

void _controlTests() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-ctl');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<TurnController> controller() async {
    final keys = ApiKeysStore(KvStore(path: '${dir.path}/s.json'));
    await keys.load();
    return TurnController(keys: keys);
  }

  group('retry', () {
    test('is unavailable until something has been asked', () async {
      final turn = await controller();
      addTearDown(turn.dispose);
      expect(turn.canRetry, isFalse);
    });

    test('replaces the previous exchange rather than appending a second',
        () async {
      // Asking again is the same question, not a new one. Leaving the old
      // pair in place would make a retried conversation read as if the user
      // had repeated themselves.
      final turn = await controller();
      addTearDown(turn.dispose);

      await turn.send('hello', mode: AppMode.chat);
      expect(turn.items, hasLength(2));

      await turn.retry();
      expect(turn.items, hasLength(2));
      expect(turn.items.whereType<UserSaid>().single.text, 'hello');
    });
  });

  group('stop', () {
    test('keeps what arrived and marks it stopped, not failed', () async {
      // Half an answer is worth more than none, and a deliberate stop is not
      // an error — labelling it as one makes someone doubt an action they
      // took on purpose.
      final turn = await controller();
      addTearDown(turn.dispose);

      final pending = turn.send('hello', mode: AppMode.chat);
      turn.stop();
      await pending;

      final reply = turn.items.whereType<Reply>().single;
      expect(reply.done, isTrue);
      expect(turn.running, isFalse);
    });

    test('does nothing when nothing is running', () async {
      final turn = await controller();
      addTearDown(turn.dispose);
      turn.stop();
      expect(turn.items, isEmpty);
    });
  });
}
