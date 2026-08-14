import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/agents/agent_loop.dart';
import 'package:shift/agents/anthropic_agent.dart';
import 'package:shift/agents/workspace_local_stub.dart'
    if (dart.library.io) 'package:shift/agents/workspace_local_io.dart';
import 'package:shift/providers/access.dart';
import 'package:shift/providers/streaming/sse_client.dart';

/// The loop, against a **real** directory and a fake model.
///
/// That pairing is the point: the model is the part that cannot be had here,
/// and the filesystem is the part where pretending would prove nothing.
void main() {
  late Directory dir;
  late LocalWorkspace workspace;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-loop');
    workspace = LocalWorkspace(dir.path);
    await workspace.writeText('lib/greeting.dart', "const hello = 'hi';\n");
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<List<AgentEvent>> run(List<List<SseEvent>> rounds) {
    final loop = AgentLoop(
      workspace: workspace,
      client: AnthropicAgent(sse: _Scripted(rounds)),
      maxRounds: 5,
    );
    return loop
        .run(
          instruction: 'change the greeting',
          access: const DirectKey('sk-ant-x'),
          model: 'claude-opus-4-8',
        )
        .toList();
  }

  group('the wire', () {
    test('arguments arrive in fragments and are parsed once', () async {
      // `input_json_delta` is a JSON string in pieces. Parsing each piece
      // throws, so a client that tried would drop every call it was asked for.
      final round = await AnthropicAgent.fold(Stream.fromIterable([
        _start(0, {'type': 'tool_use', 'id': 't1', 'name': 'read_file'}),
        _delta(0, {'type': 'input_json_delta', 'partial_json': '{"pa'}),
        _delta(0, {'type': 'input_json_delta', 'partial_json': 'th": "a.txt"}'}),
        _stop('tool_use'),
      ]));

      expect(round.calls.single.name, 'read_file');
      expect(round.calls.single.input['path'], 'a.txt');
      expect(round.wantsTools, isTrue);
    });

    test('two calls in one round keep their order', () async {
      final round = await AnthropicAgent.fold(Stream.fromIterable([
        _start(0, {'type': 'tool_use', 'id': 't1', 'name': 'glob'}),
        _delta(0, {'type': 'input_json_delta', 'partial_json': '{"pattern":"*"}'}),
        _start(1, {'type': 'tool_use', 'id': 't2', 'name': 'grep'}),
        _delta(1, {'type': 'input_json_delta', 'partial_json': '{"pattern":"x"}'}),
        _stop('tool_use'),
      ]));

      expect(round.calls.map((c) => c.name), ['glob', 'grep']);
    });

    test('malformed arguments do not lose the turn', () async {
      // A model can emit broken JSON. Throwing here would take the whole run;
      // an empty argument set reaches the tool, which refuses it and says so —
      // which the model can recover from.
      final round = await AnthropicAgent.fold(Stream.fromIterable([
        _start(0, {'type': 'tool_use', 'id': 't1', 'name': 'read_file'}),
        _delta(0, {'type': 'input_json_delta', 'partial_json': '{"path":'}),
        _stop('tool_use'),
      ]));

      expect(round.calls.single.input, isEmpty);
    });

    test('prose and a tool call in the same turn are both kept', () async {
      final round = await AnthropicAgent.fold(Stream.fromIterable([
        _delta(0, {'type': 'text_delta', 'text': 'Let me look.'}),
        _start(1, {'type': 'tool_use', 'id': 't1', 'name': 'glob'}),
        _delta(1, {'type': 'input_json_delta', 'partial_json': '{"pattern":"*"}'}),
        _stop('tool_use'),
      ]));

      expect(round.text, 'Let me look.');
      expect(round.calls, hasLength(1));
    });

    test('the assistant turn echoes the tool blocks back', () async {
      // Without this the results in the next request answer nothing — the
      // model has no record of having asked.
      final round = await AnthropicAgent.fold(Stream.fromIterable([
        _start(0, {'type': 'tool_use', 'id': 't1', 'name': 'glob'}),
        _delta(0, {'type': 'input_json_delta', 'partial_json': '{"pattern":"*"}'}),
        _stop('tool_use'),
      ]));

      final content =
          round.assistantMessage['content'] as List<dynamic>;
      final block = content.single as Map<String, dynamic>;
      expect(block['type'], 'tool_use');
      expect(block['id'], 't1');
    });
  });

  group('the loop', () {
    test('it edits a real file and then stops', () async {
      final events = await run([
        [
          _delta(0, {'type': 'text_delta', 'text': 'Reading first.'}),
          _start(1, {'type': 'tool_use', 'id': 't1', 'name': 'edit_file'}),
          _delta(1, {
            'type': 'input_json_delta',
            'partial_json': jsonEncode({
              'path': 'lib/greeting.dart',
              'old': "'hi'",
              'new': "'hello'",
            }),
          }),
          _stop('tool_use'),
        ],
        [
          _delta(0, {'type': 'text_delta', 'text': 'Changed the greeting.'}),
          _stop('end_turn'),
        ],
      ]);

      expect(await workspace.readText('lib/greeting.dart'),
          contains("'hello'"));

      final used = events.whereType<AgentUsed>().single;
      expect(used.isError, isFalse);
      expect(used.changedPath, 'lib/greeting.dart');
      expect(events.whereType<AgentDone>().single.ok, isTrue);
    });

    test('a tool is announced before it runs', () async {
      // A slow command must read as happening rather than as nothing.
      final events = await run([
        [
          _start(0, {'type': 'tool_use', 'id': 't1', 'name': 'glob'}),
          _delta(0, {
            'type': 'input_json_delta',
            'partial_json': '{"pattern":"**/*.dart"}',
          }),
          _stop('tool_use'),
        ],
        [_stop('end_turn')],
      ]);

      final order = events.map((e) => e.runtimeType.toString()).toList();
      expect(order.indexOf('AgentUsing'), lessThan(order.indexOf('AgentUsed')));
    });

    test('a refused path is reported to the model, not thrown', () async {
      final events = await run([
        [
          _start(0, {'type': 'tool_use', 'id': 't1', 'name': 'read_file'}),
          _delta(0, {
            'type': 'input_json_delta',
            'partial_json': '{"path":"../../etc/passwd"}',
          }),
          _stop('tool_use'),
        ],
        [_stop('end_turn')],
      ]);

      final used = events.whereType<AgentUsed>().single;
      expect(used.isError, isTrue);
      expect(used.result, contains('outside the workspace'));
      // And the run carried on, because being refused is something the agent
      // can choose differently about.
      expect(events.whereType<AgentDone>().single.ok, isTrue);
    });

    test('a provider failure ends the run with its sentence', () async {
      final events = await run([
        [
          const SseEvent(
            event: 'error',
            data: '{"error":{"message":"Rate limited. Try again in a moment.",'
                '"shift_detail":"HTTP 429 from api.anthropic.com"}}',
          ),
        ],
      ]);

      final done = events.whereType<AgentDone>().single;
      expect(done.ok, isFalse);
      expect(done.reason, contains('Rate limited'));
      expect(done.detail, contains('429'));
    });

    test('a model that never stops is stopped, and told so', () async {
      // A model that has misread a failure will retry the same call for ever,
      // and every round costs money.
      final asking = [
        _start(0, {'type': 'tool_use', 'id': 't1', 'name': 'glob'}),
        _delta(0, {'type': 'input_json_delta', 'partial_json': '{"pattern":"*"}'}),
        _stop('tool_use'),
      ];
      final events = await run(List.filled(6, asking));

      final done = events.whereType<AgentDone>().single;
      expect(done.ok, isFalse);
      expect(done.reason, contains('after 5 rounds'));
      expect(events.whereType<AgentUsed>(), hasLength(5),
          reason: 'the cap is on rounds, and it holds');
    });
  });

  test('the system prompt says the two things a model gets wrong', () {
    // It cannot see the files, and it must not claim work it has not checked.
    expect(AgentLoop.codeBrief, contains('cannot see the files'));
    expect(AgentLoop.codeBrief, contains('not claim'));
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

/// Answers each request with the next scripted round, so a multi-round
/// conversation can be driven without a provider.
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
