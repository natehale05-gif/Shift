import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/data/asset_store.dart';
import 'package:shift/data/conversation_store.dart';
import 'package:shift/data/image_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/job_graph.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/job_runner.dart';
import 'package:shift/turn/turn_event.dart';

/// A picture made in a turn, against a real store on a real disk.
///
/// The engine could already make one; nothing kept it and nothing drew it, so
/// asking for an image produced a reply with no picture in it. These are the
/// assertions that say it arrives, and that it is still there tomorrow.
void main() {
  late Directory dir;
  late KvStore kv;
  late ConversationStore conversations;
  late AssetStore assets;
  late ImageStore images;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-turn-images');
    kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    conversations = ConversationStore(kv);
    await conversations.load();
    assets = AssetStore(directory: '${dir.path}/assets');
    images = ImageStore(kv, assets);
    await images.load();
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  TurnController controller() => TurnController(
        conversations: conversations,
        images: images,
        executors: () => {Capability.image: _Draws()},
      );

  test('the reply carries the picture, and the store keeps it', () async {
    final turn = controller();
    addTearDown(turn.dispose);

    await turn.send('make me a picture of a cat', mode: AppMode.chat);
    await turn.imagesSettled;

    final reply = turn.items.whereType<Reply>().single;
    expect(reply.imageIds, hasLength(1),
        reason: 'the transcript has to be able to find it');

    final id = reply.imageIds.single;
    expect(images.record(id)?.prompt, 'make me a picture of a cat',
        reason: 'a picture with no record cannot be redone or explained');
    expect(await images.bytes(id), _pixels);
  });

  test('it is still there after a reload', () async {
    final turn = controller();
    addTearDown(turn.dispose);

    await turn.send('make me a picture of a cat', mode: AppMode.chat);
    await turn.imagesSettled;
    final id = turn.items.whereType<Reply>().single.imageIds.single;

    final reopened = ImageStore(
      KvStore(path: '${dir.path}/kv.json'),
      AssetStore(directory: '${dir.path}/assets'),
    );
    await reopened.load();
    final store = ConversationStore(KvStore(path: '${dir.path}/kv.json'));
    await store.load();

    final restored = itemsFromJson(store.body(store.index.single.id));
    expect(restored.whereType<Reply>().single.imageIds, [id],
        reason: 'the id has to survive the transcript, not just the store');
    expect(await reopened.bytes(id), _pixels);
  });

  test('a private chat shows the picture and writes nothing', () async {
    final turn = controller();
    addTearDown(turn.dispose);
    turn.clear(private: true);

    await turn.send('a picture I would rather not keep',
        mode: AppMode.chat);
    await turn.imagesSettled;

    final id = turn.items.whereType<Reply>().single.imageIds.single;
    // Drawable this session, which is the part a private chat still owes.
    expect(images.cached(id), _pixels);
    // And nowhere else. Asked of the store *and* of the disk, because the
    // record and the bytes are two different writes and either alone would
    // break the promise.
    expect(images.index, isEmpty);
    expect(await assets.get(id), isNull);
    expect(await assets.ids(), isEmpty);
  });

  test('two pictures in one reply are both kept', () async {
    // A reply that holds one id would quietly keep the last of a set of
    // variations, which is the shape this is built to survive.
    final turn = TurnController(
      conversations: conversations,
      images: images,
      executors: () => {Capability.image: _Draws(count: 3)},
    );
    addTearDown(turn.dispose);

    await turn.send('three pictures of a cat', mode: AppMode.chat);
    await turn.imagesSettled;

    final reply = turn.items.whereType<Reply>().single;
    expect(reply.imageIds, hasLength(3));
    expect(images.index, hasLength(3));
  });

  test('two pictures minted in the same microsecond are different pictures',
      () async {
    // Asserted on the naming rather than through a turn, because a turn
    // cannot fail this: a stream's yields land microseconds apart, so the
    // timestamp alone distinguishes them on any machine anyone has run this
    // on. Removing the counter left the turn test green — which made it a
    // check that reports the clock rather than the code.
    final at = DateTime(2026, 1, 1);
    expect(
      TurnController.mintImageId('image', at, 0),
      isNot(TurnController.mintImageId('image', at, 1)),
    );
  });
}

final _pixels = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

/// Produces [count] pictures for one step, the way a variations request would.
class _Draws implements StepExecutor {
  final int count;

  _Draws({this.count = 1});

  @override
  ({String provider, String model}) identify(JobStep step) =>
      (provider: 'fake', model: 'fake-draw');

  @override
  Stream<TurnEvent> run(JobStep step, Map<String, JobOutput> inputs) async* {
    yield StepStarted(step.id,
        label: step.label, provider: 'fake', model: 'fake-draw');
    for (var i = 0; i < count; i++) {
      yield StepCompleted(
        step.id,
        ImageOutput(
          bytes: _pixels,
          mimeType: 'image/png',
          prompt: step.instruction,
        ),
      );
    }
  }
}
