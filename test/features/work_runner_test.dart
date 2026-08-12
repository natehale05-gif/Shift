import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/agents/anthropic_agent.dart';
import 'package:shift/agents/permission.dart';
import 'package:shift/data/agent.dart';
import 'package:shift/data/agent_run.dart';
import 'package:shift/data/agent_run_store.dart';
import 'package:shift/data/agent_store.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/work/work_runner.dart';
import 'package:shift/providers/streaming/sse_client.dart';

/// The Work runner: a real folder, a real store on disk, a fake model.
///
/// What is proven here that the loop's own suite cannot: the approval reaches
/// the *screen* and comes back, the plan and the question survive a reload, and
/// the two modes' stores genuinely do not see each other.
void main() {
  late Directory dir;
  late Directory folder;
  late KvStore kv;
  late WorkAgents folders;
  late AgentRunStore runs;
  late Agent job;

  Future<void> setUpWith(PermissionMode mode) async {
    await folders.addWorkspace(LocalFolder(
      id: 'f1',
      name: 'documents',
      path: folder.path,
      permission: mode,
    ));
    job = Agent(
      id: 'j1',
      title: 'Tidy the notes',
      workspaceId: 'f1',
      status: AgentStatus.working,
      updatedAt: DateTime.now(),
    );
    await folders.save(job);
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-work-runner');
    folder = Directory('${dir.path}/documents')..createSync();
    File('${folder.path}/notes.md').writeAsStringSync('# Notes\n\nOne line.\n');

    kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    folders = WorkAgents(kv);
    runs = AgentRunStore(kv, namespace: 'work');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<ApiKeysStore> withKey() async {
    final keys = ApiKeysStore(kv);
    await keys.load();
    await keys.set('anthropic', 'sk-ant-test');
    return keys;
  }

  /// Waits for the question to arrive, and **fails rather than hangs** if it
  /// never does — an unbounded spin turns a regression into a stuck suite.
  Future<void> waitForApproval(WorkRunner r) async {
    for (var i = 0; i < 2000; i++) {
      if (r.approvalFor('j1') != null) return;
      await Future<void>.delayed(Duration.zero);
    }
    fail('the run never asked for approval');
  }

  Future<WorkRunner> runner(_Scripted transport) async => WorkRunner(
        agents: folders,
        runs: runs,
        keys: await withKey(),
        client: () => AnthropicAgent(sse: transport),
      );

  group('an approval', () {
    test('reaches the screen, and nothing is written until it is answered',
        () async {
      await setUpWith(PermissionMode.ask);
      final r = await runner(_Scripted([
        _writes('summary.md', 'the summary'),
        [_stop('end_turn')],
      ]));

      final done = r.send(job, 'summarise the notes');

      // Waited for by polling the runner rather than by a fixed delay: the
      // question arrives when the model's round does, and a `pump`-shaped
      // guess would either flake or hide a regression.
      await waitForApproval(r);

      expect(r.approvalFor('j1'), contains('summary.md'));
      expect(File('${folder.path}/summary.md').existsSync(), isFalse,
          reason: 'it wrote the file while still asking about it');

      r.answerApproval('j1', true);
      await done;

      expect(File('${folder.path}/summary.md').readAsStringSync(),
          'the summary');
      expect(r.approvalFor('j1'), isNull,
          reason: 'an answered question is still on screen');
    });

    test('declining leaves the folder untouched', () async {
      await setUpWith(PermissionMode.ask);
      final r = await runner(_Scripted([
        _writes('summary.md', 'the summary'),
        [_stop('end_turn')],
      ]));

      final done = r.send(job, 'summarise the notes');
      await waitForApproval(r);
      r.answerApproval('j1', false);
      await done;

      expect(File('${folder.path}/summary.md').existsSync(), isFalse);
      // And the run still finished, rather than hanging on the refusal.
      expect(r.runFor('j1').entries.whereType<RunEnded>().single.ok, isTrue);
    });

    test('stopping releases the question rather than stranding the run',
        () async {
      // A completer nobody completes is a run that never ends, holding a card
      // on screen that belongs to nothing.
      await setUpWith(PermissionMode.ask);
      final r = await runner(_Scripted([
        _writes('summary.md', 'the summary'),
        [_stop('end_turn')],
      ]));

      unawaited(r.send(job, 'summarise the notes'));
      await waitForApproval(r);

      await r.stop('j1');

      expect(r.approvalFor('j1'), isNull);
      expect(r.isRunning('j1'), isFalse);
      expect(File('${folder.path}/summary.md').existsSync(), isFalse);
    });

    test('a folder set to don\'t ask never asks, and the file lands', () async {
      await setUpWith(PermissionMode.dontAsk);
      final r = await runner(_Scripted([
        _writes('summary.md', 'the summary'),
        [_stop('end_turn')],
      ]));

      await r.send(job, 'summarise the notes');

      expect(File('${folder.path}/summary.md').readAsStringSync(),
          'the summary');
    });
  });

  group('what survives a reload', () {
    test('the plan, as its own transcript entry', () async {
      await setUpWith(PermissionMode.dontAsk);
      final r = await runner(_Scripted([
        _calls('plan', {
          'tasks': [
            {'title': 'Read the notes', 'done': true},
            {'title': 'Write the summary'},
          ],
        }),
        [_stop('end_turn')],
      ]));

      await r.send(job, 'summarise the notes');

      final reopened = KvStore(path: '${dir.path}/kv.json');
      await reopened.load();
      final stored = AgentRunStore(reopened, namespace: 'work').read('j1');
      final plan = stored.entries.whereType<RunPlan>().single;
      expect(plan.tasks.map((t) => t.title),
          ['Read the notes', 'Write the summary']);
      expect(plan.tasks.first.done, isTrue);
    });

    test('the question it stopped on', () async {
      await setUpWith(PermissionMode.dontAsk);
      final r = await runner(_Scripted([
        _calls('ask', {'question': 'Which quarter?'}),
      ]));

      await r.send(job, 'summarise the notes');

      expect(folders.agent('j1')?.status, AgentStatus.needsAttention);

      final reopened = KvStore(path: '${dir.path}/kv.json');
      await reopened.load();
      final stored = AgentRunStore(reopened, namespace: 'work').read('j1');
      expect(stored.entries.whereType<RunQuestion>().single.question,
          'Which quarter?');
    });

    test('the folder, with the permission mode it was added with', () async {
      await setUpWith(PermissionMode.acceptEdits);

      final reopened = KvStore(path: '${dir.path}/kv.json');
      await reopened.load();
      final second = WorkAgents(reopened);
      expect(second.workspace('f1')?.permission, PermissionMode.acceptEdits);
    });
  });

  test('Work and Code do not see each other', () async {
    // The reason the stores take a namespace at all. A repository in a list of
    // somebody's documents is a mode leaking into another one.
    await setUpWith(PermissionMode.ask);

    final reopened = KvStore(path: '${dir.path}/kv.json');
    await reopened.load();
    expect(WorkAgents(reopened).workspaces, hasLength(1));
    expect(AgentStore(reopened).workspaces, isEmpty);
  });
}

List<SseEvent> _writes(String path, String contents) =>
    _calls('write_file', {'path': path, 'contents': contents});

List<SseEvent> _calls(String tool, Map<String, dynamic> input) => [
      SseEvent(
        event: 'content_block_start',
        data: jsonEncode({
          'index': 0,
          'content_block': {'type': 'tool_use', 'id': 't1', 'name': tool},
        }),
      ),
      SseEvent(
        event: 'content_block_delta',
        data: jsonEncode({
          'index': 0,
          'delta': {
            'type': 'input_json_delta',
            'partial_json': jsonEncode(input),
          },
        }),
      ),
      _stop('tool_use'),
    ];

SseEvent _stop(String reason) => SseEvent(
      event: 'message_delta',
      data: jsonEncode({
        'delta': {'stop_reason': reason}
      }),
    );

class _Scripted implements SseClient {
  final List<List<SseEvent>> rounds;
  int _at = 0;

  _Scripted(this.rounds);

  @override
  Stream<SseEvent> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) {
    final frames = _at < rounds.length ? rounds[_at] : const <SseEvent>[];
    _at++;
    return Stream.fromIterable(frames);
  }
}
