import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/data/artifact.dart';
import 'package:shift/data/artifact_store.dart';
import 'package:shift/data/conversation_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/job_graph.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/job_runner.dart';
import 'package:shift/turn/turn_event.dart';

/// A private chat, against a **real** store on a **real** file.
///
/// The whole promise is "this does not reach disk", so an in-memory double
/// would be asserting the wrong thing: what matters is that the file a
/// relaunch reads has nothing in it.
void main() {
  late Directory dir;
  late KvStore kv;
  late ConversationStore conversations;
  late ArtifactStore artifacts;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-private');
    kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    conversations = ConversationStore(kv);
    await conversations.load();
    artifacts = ArtifactStore(kv);
    await artifacts.load();
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  TurnController controller({StepExecutor? text}) => TurnController(
        conversations: conversations,
        artifacts: artifacts,
        executors: () => {Capability.text: text ?? _Says('an answer')},
      );

  /// What a relaunch would find.
  Future<KvStore> reopen() async {
    final store = KvStore(path: '${dir.path}/kv.json');
    await store.load();
    return store;
  }

  test('an ordinary chat is kept', () async {
    // The control. Without it, a broken save would make every assertion below
    // pass for the wrong reason.
    final turn = controller();
    addTearDown(turn.dispose);

    await turn.send('hello', mode: AppMode.chat);

    expect(conversations.index, hasLength(1));
    expect((await reopen()).get('chats.index'), isNotNull);
  });

  test('a private chat leaves nothing behind', () async {
    final turn = controller();
    addTearDown(turn.dispose);
    turn.clear(private: true);

    await turn.send('something I would rather not keep', mode: AppMode.chat);

    expect(turn.items, hasLength(2), reason: 'it still answers');
    expect(conversations.index, isEmpty);

    final disk = await reopen();
    expect(disk.get('chats.index'), isNull);
    for (final key in ['chats.index']) {
      expect('${disk.get(key)}',
          isNot(contains('would rather not keep')), reason: key);
    }
  });

  /// Everything a relaunch would find, or empty when nothing was written.
  Future<String> onDisk() async {
    final file = File('${dir.path}/kv.json');
    return await file.exists() ? file.readAsString() : '';
  }

  group('a page made in a chat', () {
    test('is kept when the chat is ordinary', () async {
      // The control, and it is load-bearing: without it "nothing on disk"
      // passes just as well when artifacts are never saved at all.
      final turn = controller(text: _MakesArtifact());
      addTearDown(turn.dispose);

      await turn.send('build me a page', mode: AppMode.chat);

      expect(artifacts.forConversation('c1'), hasLength(1));
    });

    test('is not kept when the chat is private', () async {
      // The promise broken in the least visible way: the conversation is gone
      // and the thing it produced is still in the artifact store.
      final turn = controller(text: _MakesArtifact());
      addTearDown(turn.dispose);
      turn.clear(private: true);

      await turn.send('build me a page', mode: AppMode.chat);

      expect(turn.produced, hasLength(1), reason: 'usable in the session');

      // Asked of the **store**, not of the file. The file was the obvious
      // check and it could not fail: the artifact write is fire-and-forget, so
      // in a private chat nothing flushes it and the file is empty whether the
      // guard is there or not. The store's own view is what "kept" means.
      expect(artifacts.forConversation('c1'), isEmpty,
          reason: 'the page outlived the chat that made it');
      expect(await onDisk(), isNot(contains('DOCTYPE html')));
    });
  });

  test('leaving a private chat for an ordinary one starts saving again',
      () async {
    final turn = controller();
    addTearDown(turn.dispose);

    turn.clear(private: true);
    await turn.send('private', mode: AppMode.chat);
    turn.clear();
    await turn.send('ordinary', mode: AppMode.chat);

    expect(turn.private, isFalse);
    expect(conversations.index, hasLength(1),
        reason: 'exactly the ordinary one');
    final saved = conversations.index.single;
    expect(conversations.body(saved.id).toString(), contains('ordinary'));
    expect(conversations.body(saved.id).toString(), isNot(contains('private')));
  });

  test('opening a saved conversation is never private', () async {
    // Otherwise a chat that was on disk would stop being written to the moment
    // it was reopened, and edits would vanish with no explanation.
    final turn = controller();
    addTearDown(turn.dispose);

    await turn.send('keep me', mode: AppMode.chat);
    final id = turn.conversationId!;
    turn.clear(private: true);
    turn.open(id);

    expect(turn.private, isFalse);
  });

  test('an attachment does not survive into the next chat', () async {
    // Notes attached to a private chat are the person's own material, and
    // carrying them into whatever they open next is its own leak.
    final turn = controller();
    addTearDown(turn.dispose);

    turn.attachNotes(['n1']);
    turn.clear(private: true);

    expect(turn.attachedNotes, isEmpty);
  });
}

class _Says implements StepExecutor {
  final String reply;

  _Says(this.reply);

  @override
  ({String provider, String model}) identify(JobStep step) =>
      (provider: 'fake', model: 'fake-1');

  @override
  Stream<TurnEvent> run(JobStep step, Map<String, Object?> inputs) async* {
    yield StepStarted(step.id,
        label: step.label, provider: 'fake', model: 'fake-1');
    yield TextDelta(step.id, reply);
    yield StepCompleted(step.id, TextOutput(reply));
  }
}

class _MakesArtifact implements StepExecutor {
  @override
  ({String provider, String model}) identify(JobStep step) =>
      (provider: 'fake', model: 'fake-1');

  @override
  Stream<TurnEvent> run(JobStep step, Map<String, Object?> inputs) async* {
    yield StepStarted(step.id,
        label: step.label, provider: 'fake', model: 'fake-1');
    yield TextDelta(step.id, 'Here it is.');
    yield ArtifactProduced(
      step.id,
      Artifact(
        id: 'a1',
        conversationId: 'c1',
        title: 'A page',
        kind: ArtifactKind.html,
        versions: [
          ArtifactVersion(
            content: '<!DOCTYPE html><html><body>hi</body></html>',
            createdAt: DateTime(2026),
          ),
        ],
      ),
    );
    yield StepCompleted(step.id, const TextOutput('Here it is.'));
  }
}
