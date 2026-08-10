import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/conversation_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/chat/turn_controller.dart';
import 'package:shift/shell/mode.dart';
import 'package:shift/turn/capability.dart';
import 'package:shift/turn/job_graph.dart';
import 'package:shift/turn/job_output.dart';
import 'package:shift/turn/job_runner.dart';
import 'package:shift/turn/turn_event.dart';

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

  group('a turn survives however it ends', () {
    Future<ConversationStore> open() async {
      final store = ConversationStore(KvStore(path: '${dir.path}/s.json'));
      await store.load();
      return store;
    }

    /// A turn that streams and then waits, so it can be stopped mid-flight.
    late _Streaming executor;

    Future<TurnController> streaming({Duration? snapshotEvery}) async {
      executor = _Streaming();
      addTearDown(executor.release);
      return TurnController(
        conversations: await open(),
        executors: () => {Capability.text: executor},
        // A minute by default, so the stop tests below prove *stop* wrote
        // rather than a mid-flight snapshot happening to have covered for it.
        // A guard that cannot fail for the reason it names is worse than none.
        snapshotEvery: snapshotEvery ?? const Duration(minutes: 1),
      );
    }

    test('stopping halfway saves the chat', () async {
      // The reported bug. Stopping reaches the stream by *cancelling* the
      // subscription, so neither `onDone` nor `onError` fires — and those were
      // the only two callers of the write. Stop on the first turn of a chat
      // and the entire conversation was missing from the sidebar.
      final turn = await streaming();
      addTearDown(turn.dispose);

      final pending = turn.send('build me a coffee shop site',
          mode: AppMode.chat);
      await executor.streaming;
      await pumpEventQueue();
      await turn.stop();
      await pending;

      final reloaded = await open();
      expect(reloaded.index, hasLength(1));
      expect(reloaded.index.single.title, 'build me a coffee shop site');

      final restored = itemsFromJson(reloaded.body(reloaded.index.single.id));
      expect(restored.whereType<Reply>().single.text, 'half an answer',
          reason: 'what arrived is worth keeping; that is why stop keeps it');
    });

    test('a stopped reply comes back stopped, not finished', () async {
      final turn = await streaming();
      addTearDown(turn.dispose);

      final pending = turn.send('hello', mode: AppMode.chat);
      await executor.streaming;
      await pumpEventQueue();
      await turn.stop();
      await pending;

      final reloaded = await open();
      final reply = itemsFromJson(reloaded.body(reloaded.index.single.id))
          .whereType<Reply>()
          .single;
      expect(reply.interrupted, isTrue,
          reason: 'half an answer presented as a whole one is a lie the app '
              'would be telling on every reload');
    });

    test('send does not return before the stopped turn is on disk', () async {
      // The ordering `stop` has to hold: completing the turn before the write
      // lands is the fire-and-forget defect that already cost this file once.
      final turn = await streaming();
      addTearDown(turn.dispose);

      final pending = turn.send('hello', mode: AppMode.chat);
      await executor.streaming;
      await pumpEventQueue();
      unawaited(turn.stop());
      await pending;

      expect((await open()).index, hasLength(1));
    });

    test('a reply still arriving is already on disk', () async {
      // Nothing was written between "turn started" and "turn ended", so a
      // closed tab or a killed app lost the exchange with no stop involved.
      final turn = await streaming(snapshotEvery: Duration.zero);
      addTearDown(turn.dispose);

      unawaited(turn.send('hello', mode: AppMode.chat));
      await executor.streaming;
      await pumpEventQueue();
      // The snapshot itself, not a guess at how many turns of the event loop
      // a real file write takes — that guess passed here and failed on CI.
      await turn.snapshotting;

      expect(turn.running, isTrue, reason: 'this is the mid-flight case');

      final reloaded = await open();
      expect(reloaded.index, hasLength(1));
      final reply = itemsFromJson(reloaded.body(reloaded.index.single.id))
          .whereType<Reply>()
          .single;
      expect(reply.interrupted, isTrue,
          reason: 'a snapshot that survives a crash did not finish, and must '
              'not restore as a complete short answer');
    });

    test('snapshots never overlap', () async {
      // `KvStore.put` is a read-modify-write of the whole map, so two saves in
      // flight at once can drop each other's keys — including the index, which
      // is what makes a conversation findable at all.
      //
      // Asserted against a store that *holds* its write, because on a fast
      // disk the writes finish between deltas and the race never happens.
      // Written the obvious way first, this passed with the guard removed —
      // which made it a check that could not fail.
      final store = _BlockingStore(KvStore(path: '${dir.path}/s.json'));
      await store.load();
      final held = _Streaming();
      addTearDown(held.release);

      final turn = TurnController(
        conversations: store,
        executors: () => {Capability.text: held},
        snapshotEvery: Duration.zero,
      );
      addTearDown(turn.dispose);

      unawaited(turn.send('hello', mode: AppMode.chat));
      await held.streaming;
      await pumpEventQueue();

      expect(store.peakConcurrent, 1,
          reason: 'a second save started while the first was still writing');

      store.release();
      await pumpEventQueue();
      await turn.stop();
    });
  });
}

/// A store whose write can be held open, so two saves can be made to overlap
/// on purpose. Real disks here are too fast for the race to happen by itself.
class _BlockingStore extends ConversationStore {
  _BlockingStore(super.kv);

  final _gate = Completer<void>();
  int _inFlight = 0;
  int peakConcurrent = 0;

  void release() {
    if (!_gate.isCompleted) _gate.complete();
  }

  @override
  Future<void> save({
    required String id,
    required String title,
    required List<Map<String, dynamic>> items,
  }) async {
    _inFlight++;
    if (_inFlight > peakConcurrent) peakConcurrent = _inFlight;
    await _gate.future;
    await super.save(id: id, title: title, items: items);
    _inFlight--;
  }
}

/// Emits two deltas and then waits, so a test can stop a turn that is
/// genuinely mid-flight rather than one that has already finished.
class _Streaming implements StepExecutor {
  final _open = Completer<void>();
  final _held = Completer<void>();

  /// Completes once both deltas have been emitted.
  Future<void> get streaming => _open.future;

  void release() {
    if (!_held.isCompleted) _held.complete();
  }

  @override
  ({String provider, String model}) identify(JobStep step) =>
      (provider: 'Claude', model: 'claude-opus-4-8');

  @override
  Stream<TurnEvent> run(JobStep step, Map<String, JobOutput> inputs) async* {
    yield TextDelta(step.id, 'half an ');
    yield TextDelta(step.id, 'answer');
    if (!_open.isCompleted) _open.complete();
    await _held.future;
    yield StepCompleted(step.id, const TextOutput('half an answer'));
  }
}
