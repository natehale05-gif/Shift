import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/agents/agent_loop.dart';
import 'package:shift/agents/anthropic_agent.dart';
import 'package:shift/agents/permission.dart';
import 'package:shift/agents/tools.dart';
import 'package:shift/agents/work_brief.dart';
import 'package:shift/agents/workspace_local_stub.dart'
    if (dart.library.io) 'package:shift/agents/workspace_local_io.dart';
import 'package:shift/providers/access.dart';
import 'package:shift/providers/streaming/sse_client.dart';

/// The Work agent: the same loop, a different brief, two more tools, and a
/// gate in front of everything that changes a file.
///
/// Against a **real** directory, like its Code sibling and for the same reason:
/// the model is the part that cannot be had here, and the filesystem is the
/// part where pretending would prove nothing. "It paused" and "it paused
/// *without doing it*" are different claims, and only a real folder can tell
/// them apart.
void main() {
  late Directory dir;
  late LocalWorkspace workspace;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-work');
    workspace = LocalWorkspace(dir.path);
    await workspace.writeText('notes.md', '# Notes\n\nOne line.\n');
  });
  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  /// The file's content, or null when there is none.
  ///
  /// [LocalWorkspace.readText] throws on a missing file, and every assertion
  /// here is about whether a file came into existence — so "not there" has to
  /// be an answer rather than a stack trace.
  Future<String?> read(String path) async {
    try {
      return await workspace.readText(path);
    } catch (_) {
      return null;
    }
  }

  Stream<AgentEvent> run(
    List<List<SseEvent>> rounds, {
    PermissionMode mode = PermissionMode.ask,
    Future<bool> Function(String)? approve,
  }) =>
      AgentLoop(
        workspace: workspace,
        client: AnthropicAgent(sse: _Scripted(rounds)),
        brief: kWorkBrief,
        tools: kWorkTools,
        permit: (tool, input) => decide(mode, tool, input),
        approve: approve ?? (_) async => false,
        maxRounds: 5,
      ).run(
        instruction: 'tidy up my notes',
        access: const DirectKey('sk-ant-x'),
        model: 'claude-opus-4-8',
      );

  group('the gate', () {
    test('a write under ask does not happen until it is allowed', () async {
      final asked = <String>[];
      final events = await run(
        [_writes('draft.md', 'hello')],
        approve: (question) async {
          // Read the folder from *inside* the approval, which is the only
          // moment at which "asked but has not done it" is observable.
          asked.add(question);
          expect(await read('draft.md'), isNull,
              reason: 'the file exists before the person said yes');
          return true;
        },
      ).toList();

      expect(asked.single, contains('draft.md'));
      expect(await read('draft.md'), 'hello');
      expect(events.whereType<AgentUsed>().single.isError, isFalse);
    });

    test('declining does not write, and the model is told', () async {
      final events =
          await run([_writes('draft.md', 'hello')], approve: (_) async => false)
              .toList();

      expect(await read('draft.md'), isNull);
      final used = events.whereType<AgentUsed>().single;
      expect(used.isError, isTrue);
      // The model has to know the difference between "that failed" and "you
      // were not allowed", or it will retry the same call until the cap.
      expect(used.result.toLowerCase(), contains('declined'));
      expect(used.changedPath, isNull,
          reason: 'a refused call did not change a file');
    });

    test('a write under acceptEdits is not asked at all', () async {
      var asked = 0;
      await run(
        [_writes('draft.md', 'hello')],
        mode: PermissionMode.acceptEdits,
        approve: (_) async {
          asked++;
          return true;
        },
      ).toList();

      expect(asked, 0);
      expect(await read('draft.md'), 'hello');
    });

    test('a command is still asked under acceptEdits', () async {
      var asked = 0;
      await run(
        [_calls('run', {'command': 'touch', 'args': ['made-by-shell.txt']})],
        mode: PermissionMode.acceptEdits,
        approve: (_) async {
          asked++;
          return false;
        },
      ).toList();

      expect(asked, 1);
      expect(await read('made-by-shell.txt'), isNull);
    });

    test('a read is never asked', () async {
      var asked = 0;
      final events = await run(
        [_calls('read_file', {'path': 'notes.md'})],
        approve: (_) async {
          asked++;
          return true;
        },
      ).toList();

      expect(asked, 0);
      expect(events.whereType<AgentUsed>().single.result, contains('One line'));
    });

    test('a path outside the folder is refused without being offered', () async {
      var asked = 0;
      final events = await run(
        [_writes('../escaped.md', 'nope')],
        mode: PermissionMode.dontAsk,
        approve: (_) async {
          asked++;
          return true;
        },
      ).toList();

      expect(asked, 0, reason: 'nobody can approve their way out of the folder');
      expect(events.whereType<AgentUsed>().single.isError, isTrue);
      expect(File('${dir.parent.path}/escaped.md').existsSync(), isFalse);
    });
  });

  group('the two tools that make it a work agent', () {
    test('a plan arrives as a task list', () async {
      final events = await run([
        _calls('plan', {
          'tasks': [
            {'title': 'Read the notes', 'done': true},
            {'title': 'Write a summary'},
          ],
        }),
      ]).toList();

      final planned = events.whereType<AgentPlanned>().single;
      expect(planned.tasks.map((t) => t.title),
          ['Read the notes', 'Write a summary']);
      expect(planned.tasks.first.done, isTrue);
      expect(planned.tasks.last.done, isFalse);
    });

    test('asking ends the round and says what it asked', () async {
      final events = await run(
        [
          _calls('ask', {'question': 'Which quarter should the report cover?'}),
          // A second round is scripted and must not be reached: the point of
          // `ask` is that nothing further happens until somebody answers.
          _writes('report.md', 'guessed'),
        ],
        // Allowed, deliberately. With the default refusal the second round
        // would write nothing either way, and the assertion below would pass
        // whether or not `ask` ended the run — a check that cannot fail.
        approve: (_) async => true,
      ).toList();

      expect(events.whereType<AgentAsked>().single.question,
          'Which quarter should the report cover?');
      expect(events.whereType<AgentDone>().single.ok, isTrue);
      expect(await read('report.md'), isNull,
          reason: 'it carried on past a question it had not had answered');
    });
  });

  group('the brief', () {
    test('carries the two things a model gets wrong', () {
      // Learned expensively enough in v1 to be worth pinning: it cannot see a
      // file it has not read, and it must not claim what it has not verified.
      expect(kWorkBrief, contains('cannot see a file'));
      expect(kWorkBrief.toLowerCase(), contains('not claim'));
    });

    test('says what a document folder is missing', () {
      // The whole reason this is not the code brief: no version control, so an
      // overwrite is final.
      expect(kWorkBrief, contains('no undo'));
      expect(kWorkBrief, contains('edit_file'));
    });

    test('is not the code brief', () {
      expect(kWorkBrief, isNot(AgentLoop.codeBrief));
    });
  });
}

List<SseEvent> _writes(String path, String content) =>
    _calls('write_file', {'path': path, 'contents': content});

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
      SseEvent(
        event: 'message_delta',
        data: jsonEncode({
          'delta': {'stop_reason': 'tool_use'}
        }),
      ),
    ];

/// Answers each request with the next scripted round.
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
