import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/data/agent.dart';
import 'package:shift/data/agent_store.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/artifact.dart';
import 'package:shift/data/artifact_store.dart';
import 'package:shift/data/asset_store.dart';
import 'package:shift/data/conversation_store.dart';
import 'package:shift/data/image_store.dart';
import 'package:shift/data/made_image.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/note_store.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/features/settings/erase_everything.dart';

/// "Delete everything", against a real file.
///
/// The claim is absolute, so the test is too: after this, the file a relaunch
/// reads has nothing of any kind in it — not the categories I remembered to
/// list, all of them.
void main() {
  late Directory dir;
  late KvStore kv;
  late ConversationStore conversations;
  late ArtifactStore artifacts;
  late NoteStore notes;
  late AgentStore agents;
  late ApiKeysStore keys;
  late ImageStore images;
  late AssetStore assets;
  late TurnController turn;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-erase');
    kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    conversations = ConversationStore(kv);
    await conversations.load();
    artifacts = ArtifactStore(kv);
    await artifacts.load();
    notes = NoteStore(kv);
    await notes.load();
    agents = AgentStore(kv);
    await agents.load();
    keys = ApiKeysStore(kv);
    await keys.load();
    assets = AssetStore(directory: '${dir.path}/assets');
    images = ImageStore(kv, assets);
    await images.load();
    turn = TurnController(conversations: conversations, artifacts: artifacts);
  });
  tearDown(() async {
    turn.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<void> fill() async {
    await conversations.save(
      id: 'c1',
      title: 'A chat',
      items: [
        {'role': 'user', 'text': 'a secret question'},
      ],
    );
    await artifacts.save(Artifact(
      id: 'a1',
      conversationId: 'c1',
      title: 'A page',
      kind: ArtifactKind.html,
      versions: [
        ArtifactVersion(
            content: '<!DOCTYPE html><body>the page</body>',
            createdAt: DateTime(2026)),
      ],
    ));
    await notes.save('n1', 'A private note');
    await agents.addWorkspace(
      LocalFolder(id: 'w1', name: 'repo', path: dir.path),
    );
    await keys.set('anthropic', 'sk-ant-secret');
    await images.save(
      MadeImage(
        id: 'img1',
        prompt: 'a private picture',
        provider: 'gemini',
        model: 'nano',
        mimeType: 'image/png',
        createdAt: DateTime(2026),
      ),
      Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]),
    );
  }

  Future<void> erase() => eraseEverything(
        kv: kv,
        conversations: conversations,
        artifacts: artifacts,
        notes: notes,
        agents: agents,
        keys: keys,
        images: images,
        turn: turn,
      );

  test('it fills up first', () async {
    // The control. Without it every assertion below passes on an app that
    // never stored anything in the first place.
    await fill();

    expect(conversations.index, isNotEmpty);
    expect(notes.index, isNotEmpty);
    expect(agents.workspaces, isNotEmpty);
    expect(keys.has('anthropic'), isTrue);
    expect(images.index, isNotEmpty);
    expect(await assets.get('img1'), isNotNull,
        reason: 'the bytes, not just the record');
    expect(await File('${dir.path}/kv.json').readAsString(),
        contains('a secret question'));
  });

  test('nothing survives, in memory or on disk', () async {
    await fill();
    turn.open('c1');
    await erase();

    expect(conversations.index, isEmpty);
    expect(artifacts.forConversation('c1'), isEmpty);
    expect(notes.index, isEmpty);
    expect(agents.workspaces, isEmpty);
    expect(agents.agents, isEmpty);
    expect(keys.has('anthropic'), isFalse);
    expect(images.index, isEmpty);
    // The half clearing the key-value map cannot reach. Without it the app
    // looks empty and the largest thing it ever wrote is still on disk.
    expect(await assets.get('img1'), isNull, reason: 'the bytes go too');
    expect(await assets.ids(), isEmpty);
    expect(turn.conversationId, isNull,
        reason: 'the screen must let go of what was deleted');

    // Read as text rather than key by key: the point is that nothing is left,
    // including anything a later wave adds that this test never heard of.
    final raw = await File('${dir.path}/kv.json').readAsString();
    for (final trace in [
      'a secret question',
      'the page',
      'A private note',
      'sk-ant-secret',
      'repo',
      'a private picture',
    ]) {
      expect(raw, isNot(contains(trace)), reason: trace);
    }
  });

  test('it stays gone after a reload', () async {
    await fill();
    await erase();

    final reopened = KvStore(path: '${dir.path}/kv.json');
    await reopened.load();
    expect(reopened.keys(), isEmpty);
  });

  test('erasing an empty app is not an error', () async {
    await erase();
    expect(conversations.index, isEmpty);
  });
}
