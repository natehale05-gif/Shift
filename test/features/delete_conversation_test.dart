import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/data/artifact.dart';
import 'package:shift/data/artifact_store.dart';
import 'package:shift/data/conversation_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/chat/delete_conversation.dart';
import 'package:shift/features/chat/turn_controller.dart';

/// Deleting a conversation, against a real store on a real file.
void main() {
  late Directory dir;
  late ConversationStore conversations;
  late ArtifactStore artifacts;
  late TurnController turn;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-delete');
    final kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    conversations = ConversationStore(kv);
    await conversations.load();
    artifacts = ArtifactStore(kv);
    await artifacts.load();
    turn = TurnController(conversations: conversations, artifacts: artifacts);
  });
  tearDown(() async {
    turn.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> seed(String id, {bool withPage = true}) async {
    await conversations.save(
      id: id,
      title: 'Chat $id',
      items: [
        {'role': 'user', 'text': 'hello from $id'},
      ],
    );
    if (withPage) {
      await artifacts.save(Artifact(
        id: 'art-$id',
        conversationId: id,
        title: 'A page',
        kind: ArtifactKind.html,
        versions: [
          ArtifactVersion(
            content: '<!DOCTYPE html><html><body>$id</body></html>',
            createdAt: DateTime(2026),
          ),
        ],
      ));
    }
  }

  Future<void> remove(String id) => deleteConversation(
        id,
        conversations: conversations,
        artifacts: artifacts,
        turn: turn,
      );

  test('the transcript goes, and so does what it made', () async {
    // The pages are the part people would not expect to lose *and* the part
    // that would sit there forever if this forgot them.
    await seed('a');
    await remove('a');

    expect(conversations.index, isEmpty);
    expect(conversations.body('a'), isEmpty);
    expect(artifacts.forConversation('a'), isEmpty);
  });

  test('only that one goes', () async {
    await seed('a');
    await seed('b');
    await remove('a');

    expect(conversations.index.single.id, 'b');
    expect(artifacts.forConversation('b'), hasLength(1));
  });

  test('deleting the open conversation lets the screen go of it', () async {
    // Otherwise the app keeps showing a conversation that no longer exists,
    // and writes it back on the next keystroke.
    await seed('a');
    turn.open('a');
    expect(turn.conversationId, 'a');

    await remove('a');

    expect(turn.conversationId, isNull);
    expect(turn.items, isEmpty);
    expect(turn.produced, isEmpty);
  });

  test('deleting another conversation leaves the open one alone', () async {
    await seed('a');
    await seed('b');
    turn.open('a');

    await remove('b');

    expect(turn.conversationId, 'a');
    expect(turn.items, isNotEmpty);
  });

  test('it stays deleted after a reload', () async {
    await seed('a');
    await remove('a');

    final reopened = KvStore(path: '${dir.path}/kv.json');
    await reopened.load();
    final store = ConversationStore(reopened);
    await store.load();

    expect(store.index, isEmpty);
    final raw = await File('${dir.path}/kv.json').readAsString();
    expect(raw, isNot(contains('hello from a')));
    expect(raw, isNot(contains('<body>a</body>')));
  });
}
