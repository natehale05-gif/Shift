import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/data/conversation_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/shell/mode.dart';

/// A real file, because "survives a restart" is the only claim being made and
/// a fake map cannot test it.
void main() {
  late Directory dir;
  String path() => '${dir.path}/settings.json';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-chats');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<ConversationStore> open() async {
    final store = ConversationStore(KvStore(path: path()));
    await store.load();
    return store;
  }

  group('a conversation survives', () {
    test('a turn taken now is there after a restart', () async {
      final first = await open();
      final turn = TurnController(conversations: first);
      addTearDown(turn.dispose);

      await turn.send('build me a bakery page', mode: AppMode.chat);

      final second = await open();
      expect(second.index, hasLength(1));
      expect(second.index.single.title, 'build me a bakery page');

      final restored = itemsFromJson(second.body(second.index.single.id));
      expect(restored.whereType<UserSaid>().single.text,
          'build me a bakery page');
    });

    test('a restored reply is finished, never mid-flight', () async {
      // Writing `done: false` to disk would let a "still arriving" state
      // survive a restart with nothing arriving — a spinner that never stops.
      final first = await open();
      final turn = TurnController(conversations: first);
      addTearDown(turn.dispose);
      await turn.send('hello', mode: AppMode.chat);

      final second = await open();
      final restored =
          itemsFromJson(second.body(second.index.single.id));
      expect(restored.whereType<Reply>().single.done, isTrue);
    });

    test('the failure is stored, so a restart does not look like success',
        () async {
      final first = await open();
      final turn = TurnController(conversations: first);
      addTearDown(turn.dispose);
      await turn.send('hello', mode: AppMode.chat);

      final second = await open();
      final reply =
          itemsFromJson(second.body(second.index.single.id))
              .whereType<Reply>()
              .single;
      expect(reply.failure, isNotNull,
          reason: 'no key is configured, so this turn failed and should '
              'still say so after a reload');
    });

    test('the detail behind a failure survives too', () async {
      // The failure worth diagnosing is usually the one that already scrolled
      // off screen — or that the app was closed on. A detail kept only in
      // memory is one nobody can send you.
      final first = await open();
      final turn = TurnController(conversations: first);
      addTearDown(turn.dispose);
      await turn.send('hello', mode: AppMode.chat);

      final live = turn.items.whereType<Reply>().single..failureDetail =
          'ClientException: Failed to fetch · api.anthropic.com';
      await first.save(
        id: turn.conversationId!,
        title: 'hello',
        items: [
          for (final item in turn.items)
            if (item is UserSaid) item.toJson() else (item as Reply).toJson(),
        ],
      );
      expect(live.failureDetail, isNotNull);

      final second = await open();
      final restored = itemsFromJson(second.body(second.index.single.id))
          .whereType<Reply>()
          .single;
      expect(restored.failureDetail, contains('Failed to fetch'));
    });
  });

  group('the list', () {
    test('New chat starts another rather than discarding the last', () async {
      final store = await open();
      final turn = TurnController(conversations: store);
      addTearDown(turn.dispose);

      await turn.send('first', mode: AppMode.chat);
      turn.clear();
      await turn.send('second', mode: AppMode.chat);

      expect(store.index, hasLength(2));
      expect(store.index.map((s) => s.title), containsAll(['first', 'second']));
    });

    test('opening a stored conversation replaces what is on screen', () async {
      final store = await open();
      final turn = TurnController(conversations: store);
      addTearDown(turn.dispose);

      await turn.send('first', mode: AppMode.chat);
      final firstId = turn.conversationId!;
      turn.clear();
      await turn.send('second', mode: AppMode.chat);

      turn.open(firstId);
      expect(turn.items.whereType<UserSaid>().single.text, 'first');
      expect(turn.conversationId, firstId);
    });

    test('a corrupt index costs the list, not the app', () async {
      await File(path()).writeAsString('{"chats.index":"not json"}');
      final store = await open();
      expect(store.index, isEmpty);
    });

    test('removing takes the body with it', () async {
      final store = await open();
      final turn = TurnController(conversations: store);
      addTearDown(turn.dispose);
      await turn.send('hello', mode: AppMode.chat);

      final id = turn.conversationId!;
      await store.remove(id);

      expect(store.index, isEmpty);
      expect((await open()).body(id), isEmpty);
    });
  });
}
