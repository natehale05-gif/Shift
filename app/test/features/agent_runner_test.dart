import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/agents/anthropic_agent.dart';
import 'package:shift/data/agent.dart';
import 'package:shift/data/agent_run.dart';
import 'package:shift/data/agent_run_store.dart';
import 'package:shift/data/agent_store.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/features/code/agent_runner.dart';
import 'package:shift/providers/streaming/sse_client.dart';

/// The runner, against a **real** directory, a **real** store on disk, and a
/// fake model.
///
/// The same pairing the loop's own suite uses and for the same reason: the
/// model is the part that cannot be had here, and the filesystem and the
/// transcript on disk are the parts where pretending would prove nothing.
void main() {
  late Directory dir;
  late Directory repo;
  late KvStore kv;
  late AgentStore agents;
  late AgentRunStore runs;
  late Agent agent;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-runner');
    repo = Directory('${dir.path}/repo')..createSync();
    File('${repo.path}/greeting.txt').writeAsStringSync("hi\n");

    kv = KvStore(path: '${dir.path}/kv.json');
    await kv.load();
    agents = AgentStore(kv);
    runs = AgentRunStore(kv);

    await agents.addWorkspace(
      LocalFolder(id: 'w1', name: 'repo', path: repo.path),
    );
    agent = Agent(
      id: 'a1',
      title: 'Change the greeting',
      workspaceId: 'w1',
      status: AgentStatus.needsAttention,
      updatedAt: DateTime.now(),
    );
    await agents.save(agent);
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

  AgentRunner runner(_Scripted transport, {ApiKeysStore? keys}) => AgentRunner(
        agents: agents,
        runs: runs,
        keys: keys,
        client: () => AnthropicAgent(sse: transport),
      );

  group('a run', () {
    test('records what it did, and the file really changed', () async {
      final transport = _Scripted([
        [
          _delta(0, {'type': 'text_delta', 'text': 'Editing it.'}),
          _start(1, {'type': 'tool_use', 'id': 't1', 'name': 'edit_file'}),
          _delta(1, {
            'type': 'input_json_delta',
            'partial_json': jsonEncode(
                {'path': 'greeting.txt', 'old': 'hi', 'new': 'hello'}),
          }),
          _stop('tool_use'),
        ],
        [
          _delta(0, {'type': 'text_delta', 'text': 'Done.'}),
          _stop('end_turn'),
        ],
      ]);

      final r = runner(transport, keys: await withKey());
      await r.send(agent, 'change the greeting');

      expect(File('${repo.path}/greeting.txt').readAsStringSync(),
          contains('hello'));

      final run = r.runFor('a1');
      expect(run.entries.whereType<RunAsked>().single.text,
          'change the greeting');
      expect(run.changedPaths, ['greeting.txt']);
      expect(run.entries.whereType<RunEnded>().single.ok, isTrue);
      expect(agents.agent('a1')?.status, AgentStatus.needsAttention);
    });

    test('a tool announced and then finished is one entry, not two', () async {
      // It is shown the moment it starts, because a slow command has to read as
      // happening — and completed in place, or the transcript lists every call
      // twice.
      final transport = _Scripted([
        [
          _start(0, {'type': 'tool_use', 'id': 't1', 'name': 'glob'}),
          _delta(0, {
            'type': 'input_json_delta',
            'partial_json': '{"pattern":"*.txt"}',
          }),
          _stop('tool_use'),
        ],
        [_stop('end_turn')],
      ]);

      final r = runner(transport, keys: await withKey());
      await r.send(agent, 'what is here');

      final tools = r.runFor('a1').entries.whereType<RunTool>().toList();
      expect(tools, hasLength(1));
      expect(tools.single.running, isFalse);
      expect(tools.single.result, contains('greeting.txt'));
    });

    test('it survives a reload, with what it changed', () async {
      final transport = _Scripted([
        [
          _start(0, {'type': 'tool_use', 'id': 't1', 'name': 'write_file'}),
          _delta(0, {
            'type': 'input_json_delta',
            'partial_json': jsonEncode(
                {'path': 'notes/new.md', 'contents': '# hi\n'}),
          }),
          _stop('tool_use'),
        ],
        [_stop('end_turn')],
      ]);

      final r = runner(transport, keys: await withKey());
      await r.send(agent, 'add a note');

      // A second store over the same file, which is what a relaunch is.
      final reopened = KvStore(path: '${dir.path}/kv.json');
      await reopened.load();
      final read = AgentRunStore(reopened).read('a1');

      expect(read.changedPaths, ['notes/new.md']);
      expect(read.entries.whereType<RunAsked>().single.text, 'add a note');
      expect(read.entries.whereType<RunTool>().single.result, isNotNull);
    });
  });

  group('it refuses honestly', () {
    test('a GitHub workspace says the server is not built, and spends nothing',
        () async {
      await agents.addWorkspace(const GitHubRepo(
          id: 'w2', name: 'shift', repo: 'natehale05-gif/Shift'));
      final remote = Agent(
        id: 'a2',
        title: 'Fix the header',
        workspaceId: 'w2',
        status: AgentStatus.needsAttention,
        updatedAt: DateTime.now(),
      );
      await agents.save(remote);

      final transport = _Scripted([]);
      final r = runner(transport, keys: await withKey());
      await r.send(remote, 'fix it');

      final ended = r.runFor('a2').entries.whereType<RunEnded>().single;
      expect(ended.reason, contains('server workspace'));
      expect(agents.agent('a2')?.status, AgentStatus.failed);
      expect(transport.calls, 0,
          reason: '"it refused" and "it refused without calling a provider" '
              'are different things');
    });

    test('no key says which key, and spends nothing', () async {
      final transport = _Scripted([]);
      final r = runner(transport);
      await r.send(agent, 'do something');

      final ended = r.runFor('a1').entries.whereType<RunEnded>().single;
      expect(ended.reason, contains('Anthropic key'));
      expect(agents.agent('a1')?.status, AgentStatus.failed);
      expect(transport.calls, 0);
    });
  });

  test('a follow-up carries what was said, not what the tools returned',
      () async {
    // The workspace is the state. The system prompt already tells the model it
    // cannot see a file it has not read, so re-reading is both cheaper than
    // carrying a transcript of results and more accurate — the files may have
    // moved on since.
    final transport = _Scripted([
      [
        _delta(0, {'type': 'text_delta', 'text': 'I renamed the greeting.'}),
        _start(1, {'type': 'tool_use', 'id': 't1', 'name': 'read_file'}),
        _delta(1, {
          'type': 'input_json_delta',
          'partial_json': '{"path":"greeting.txt"}',
        }),
        _stop('tool_use'),
      ],
      [_stop('end_turn')],
      [_stop('end_turn')],
    ]);

    final r = runner(transport, keys: await withKey());
    await r.send(agent, 'rename it');
    await r.send(agent, 'now capitalise it');

    final sent = jsonDecode(transport.bodies.last) as Map<String, dynamic>;
    final first = (sent['messages'] as List).first as Map<String, dynamic>;
    final text = jsonEncode(first['content']);

    expect(text, contains('rename it'));
    expect(text, contains('I renamed the greeting.'));
    expect(text, contains('now capitalise it'));
    expect(text, isNot(contains('read_file')),
        reason: 'tool results are not replayed — the files are');
  });

  test('changed paths keep first-touch order and do not repeat', () {
    final run = AgentRun(agentId: 'a1', entries: [
      RunTool(tool: 'write_file', input: const {})..changedPath = 'b.dart',
      RunTool(tool: 'edit_file', input: const {})..changedPath = 'a.dart',
      RunTool(tool: 'edit_file', input: const {})..changedPath = 'b.dart',
      RunTool(tool: 'read_file', input: const {}),
    ]);

    expect(run.changedPaths, ['b.dart', 'a.dart']);
  });

  test('a call still running is not stored as one that finished silently', () {
    // `fromJson` cannot tell "no output" from "never got there", so writing an
    // unfinished call with an empty result would restore an interrupted run as
    // a completed one.
    final json = RunTool(tool: 'run', input: const {'command': 'sleep'}).toJson();
    expect(json.containsKey('result'), isFalse);
    expect((RunEntry.fromJson(json)! as RunTool).running, isTrue);
  });
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

/// Answers each request with the next scripted round, and remembers what it was
/// asked — so "it did not run" and "it ran and produced nothing" stay apart.
class _Scripted implements SseClient {
  final List<List<SseEvent>> rounds;
  final List<String> bodies = [];
  int _at = 0;

  _Scripted(this.rounds);

  int get calls => bodies.length;

  @override
  Stream<SseEvent> postJson({
    required Uri uri,
    required Map<String, String> headers,
    required String body,
  }) {
    bodies.add(body);
    final frames = _at < rounds.length ? rounds[_at] : const <SseEvent>[];
    _at++;
    return Stream.fromIterable(frames);
  }
}
