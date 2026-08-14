import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/agents/anthropic_agent.dart';
import 'package:shift/agents/workspace_local_stub.dart'
    if (dart.library.io) 'package:shift/agents/workspace_local_io.dart';
import 'package:shift/data/agent.dart';
import 'package:shift/data/agent_run_store.dart';
import 'package:shift/data/agent_store.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/code/agent_runner.dart';
import 'package:shift/features/code/run_changes.dart';
import 'package:shift/providers/streaming/sse_client.dart';

/// What a run changed, against real files.
///
/// The baseline is the half a diff cannot be had without, and it can only be
/// captured at the moment of the write — so this drives the **real** loop
/// against a **real** directory and then reads the bytes back off disk. An
/// in-memory double would agree with itself and prove nothing about either.
void main() {
  late Directory dir;
  late Directory repo;
  late KvStore kv;
  late AgentStore agents;
  late AgentRunStore runs;
  late Agent agent;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-changes');
    repo = Directory('${dir.path}/repo')..createSync();

    kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    agents = AgentStore(kv);
    runs = AgentRunStore(kv);

    await agents.addWorkspace(
      LocalFolder(id: 'w1', name: 'repo', path: repo.path),
    );
    agent = Agent(
      id: 'a1',
      title: 'Work',
      workspaceId: 'w1',
      status: AgentStatus.needsAttention,
      updatedAt: DateTime.now(),
    );
    await agents.save(agent);
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  void seed(String path, String contents) =>
      File('${repo.path}/$path').writeAsStringSync(contents);

  Future<AgentRunner> drive(List<List<SseEvent>> rounds) async {
    final keys = ApiKeysStore(kv);
    await keys.load();
    await keys.set('anthropic', 'sk-ant-test');

    final runner = AgentRunner(
      agents: agents,
      runs: runs,
      keys: keys,
      client: () => AnthropicAgent(sse: _Scripted(rounds)),
    );
    await runner.send(agent, 'do the work');
    return runner;
  }

  /// One round asking for [tool], then a round that stops.
  List<List<SseEvent>> call(String tool, Map<String, dynamic> input) => [
        [
          _start(0, {'type': 'tool_use', 'id': 't1', 'name': tool}),
          _delta(0, {
            'type': 'input_json_delta',
            'partial_json': jsonEncode(input),
          }),
          _stop('tool_use'),
        ],
        [_stop('end_turn')],
      ];

  group('the baseline', () {
    test('a file that did not exist has an empty one', () async {
      final runner = await drive(
          call('write_file', {'path': 'new.txt', 'contents': 'a\nb\n'}));

      expect(runner.runFor('a1').baseline['new.txt'], '');
      final change = (await _changes(runner, agent)).single;
      expect(change.stat.added, 2);
      expect(change.stat.removed, 0);
    });

    test('an edited file records what it held before', () async {
      seed('greeting.txt', 'hi\nthere\n');
      final runner = await drive(call(
          'edit_file', {'path': 'greeting.txt', 'old': 'hi', 'new': 'hello'}));

      expect(runner.runFor('a1').baseline['greeting.txt'], 'hi\nthere\n');
    });

    test('two edits to one file keep the first baseline', () async {
      // Otherwise the second edit diffs against the first edit's output, and
      // the run reports having done less than it did.
      seed('f.txt', 'one\ntwo\n');
      final runner = await drive([
        [
          _start(0, {'type': 'tool_use', 'id': 't1', 'name': 'edit_file'}),
          _delta(0, {
            'type': 'input_json_delta',
            'partial_json':
                jsonEncode({'path': 'f.txt', 'old': 'one', 'new': 'ONE'}),
          }),
          _start(1, {'type': 'tool_use', 'id': 't2', 'name': 'edit_file'}),
          _delta(1, {
            'type': 'input_json_delta',
            'partial_json':
                jsonEncode({'path': 'f.txt', 'old': 'two', 'new': 'TWO'}),
          }),
          _stop('tool_use'),
        ],
        [_stop('end_turn')],
      ]);

      expect(runner.runFor('a1').baseline['f.txt'], 'one\ntwo\n');
      final change = (await _changes(runner, agent)).single;
      expect(change.stat.added, 2, reason: 'both edits, not just the last');
      expect(change.stat.removed, 2);
    });

    test('it survives a reload, under its own key', () async {
      // Stored apart from the transcript on purpose: baselines are whole files
      // and every list screen decodes transcripts. The separation is invisible
      // unless it is asserted.
      seed('f.txt', 'before\n');
      await drive(
          call('write_file', {'path': 'f.txt', 'contents': 'after\n'}));

      final reopened = KvStore(path: '${dir.path}/kv.json');
      await reopened.load();

      expect(AgentRunStore(reopened).readBaseline('a1'), {'f.txt': 'before\n'});
      expect(reopened.get('code.run.a1'), isNot(contains('before')),
          reason: 'the transcript must not carry file contents');
    });

    test('the run stamps a real line count on the agent', () async {
      // Every row in every list has read `+0 -0` since the mode was built.
      seed('f.txt', 'one\ntwo\nthree\n');
      await drive(call(
          'write_file', {'path': 'f.txt', 'contents': 'one\nTWO\nthree\nfour\n'}));

      expect('${agents.agent('a1')!.diff}', '+2 -1');
    });
  });

  group('what is still changed', () {
    test('a file put back to its baseline drops out of the list', () async {
      // After reverting everything it is not a changed file, and listing it
      // would show a change that is not there.
      seed('f.txt', 'one\ntwo\n');
      final runner = await drive(
          call('edit_file', {'path': 'f.txt', 'old': 'one', 'new': 'ONE'}));

      expect(await _changes(runner, agent), hasLength(1));

      File('${repo.path}/f.txt').writeAsStringSync('one\ntwo\n');
      expect(await _changes(runner, agent), isEmpty);
    });

    test('a file deleted after the run reads as a deletion', () async {
      seed('f.txt', 'one\ntwo\n');
      final runner = await drive(
          call('edit_file', {'path': 'f.txt', 'old': 'one', 'new': 'ONE'}));

      File('${repo.path}/f.txt').deleteSync();
      final change = (await _changes(runner, agent)).single;
      expect(change.stat.removed, 2);
      expect(change.stat.added, 0);
    });
  });

  group('putting it back', () {
    Future<(AgentRunner, List<FileChange>)> threeChanges() async {
      final lines = [for (var i = 0; i < 20; i++) 'line $i'];
      seed('f.txt', '${lines.join('\n')}\n');

      final edited = [...lines];
      edited[1] = 'CHANGED 1';
      edited[10] = 'CHANGED 10';
      edited[18] = 'CHANGED 18';

      final runner = await drive(call(
          'write_file', {'path': 'f.txt', 'contents': '${edited.join('\n')}\n'}));
      return (runner, await _changes(runner, agent));
    }

    test('reverting one hunk leaves the others on disk', () async {
      final (runner, changes) = await threeChanges();
      expect(changes.single.hunks, hasLength(3));

      await revertHunk(
        workspace: LocalWorkspace(repo.path),
        change: changes.single,
        baseline: runner.runFor('a1').baseline['f.txt']!,
        index: 1,
      );

      final now = File('${repo.path}/f.txt').readAsStringSync();
      expect(now, contains('CHANGED 1\n'));
      expect(now, contains('CHANGED 18'));
      expect(now, contains('line 10'), reason: 'the middle hunk went back');
      expect(now, isNot(contains('CHANGED 10')));
    });

    test('reverting every hunk restores the file byte for byte', () async {
      final (runner, changes) = await threeChanges();
      final baseline = runner.runFor('a1').baseline['f.txt']!;

      await revertFile(
        workspace: LocalWorkspace(repo.path),
        change: changes.single,
        baseline: baseline,
      );

      expect(File('${repo.path}/f.txt').readAsStringSync(), baseline);
    });

    test('reverting twice reverts two hunks', () async {
      // It composes because each pass diffs the baseline against whatever is on
      // disk by then, rather than against the run's original output.
      final (runner, changes) = await threeChanges();
      final workspace = LocalWorkspace(repo.path);
      final baseline = runner.runFor('a1').baseline['f.txt']!;

      await revertHunk(
          workspace: workspace,
          change: changes.single,
          baseline: baseline,
          index: 0);

      final left = (await _changes(runner, agent)).single;
      expect(left.hunks, hasLength(2));
      await revertHunk(
          workspace: workspace, change: left, baseline: baseline, index: 0);

      final now = File('${repo.path}/f.txt').readAsStringSync();
      expect(now, contains('line 1\n'));
      expect(now, contains('line 10'));
      expect(now, contains('CHANGED 18'), reason: 'the third is untouched');
    });
  });
}

Future<List<FileChange>> _changes(AgentRunner runner, Agent agent) async {
  final run = runner.runFor(agent.id);
  return changesFor(
    workspace: runner.workspaceFor(agent).workspace!,
    paths: run.changedPaths,
    baseline: run.baseline,
  );
}

SseEvent _start(int index, Map<String, dynamic> block) => SseEvent(
      event: 'content_block_start',
      data: jsonEncode({'index': index, 'content_block': block}),
    );

SseEvent _delta(int index, Map<String, dynamic> delta) => SseEvent(
      event: 'content_block_delta',
      data: jsonEncode({'index': index, 'delta': delta}),
    );

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
