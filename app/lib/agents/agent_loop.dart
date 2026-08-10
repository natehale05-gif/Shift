import '../providers/access.dart';
import 'anthropic_agent.dart';
import 'tools.dart';
import 'workspace.dart';

/// What the surface shows while an agent works.
///
/// Sealed, so the row that renders a run and the store that records it both
/// have to learn about anything new — rather than one of them silently
/// ignoring it, which is how a tool call goes missing from a transcript.
sealed class AgentEvent {
  const AgentEvent();
}

/// The agent talking — its reasoning between tool calls, streamed.
class AgentSaid extends AgentEvent {
  final String text;

  const AgentSaid(this.text);
}

/// A tool is running. Emitted **before** it runs, so a slow command shows as
/// happening rather than as nothing.
class AgentUsing extends AgentEvent {
  final String tool;
  final Map<String, dynamic> input;

  const AgentUsing(this.tool, this.input);
}

/// It finished, with what the model was told.
class AgentUsed extends AgentEvent {
  final String tool;
  final String result;
  final bool isError;

  /// The file this touched, if any. What the diff review is built from.
  final String? changedPath;

  const AgentUsed(
    this.tool,
    this.result, {
    this.isError = false,
    this.changedPath,
  });
}

/// The run ended.
class AgentDone extends AgentEvent {
  /// Set when it stopped for a reason worth saying: a failure, or the round
  /// limit. Null when it simply finished.
  final String? reason;

  /// The technical fact behind [reason], for a bug report.
  final String? detail;

  const AgentDone({this.reason, this.detail});

  bool get ok => reason == null;
}

/// Runs an agent until it stops asking for tools.
///
/// The whole loop is: send, run whatever it asked for, send the results,
/// repeat. Everything interesting is in the stopping conditions.
class AgentLoop {
  final AgentWorkspace workspace;
  final AnthropicAgent client;
  final List<AgentTool> tools;

  /// The most rounds before it is stopped and told so.
  ///
  /// Not a safety rail for its own sake: a model that has misread a failure
  /// will retry the same call indefinitely, and each round costs money. Twenty
  /// five is enough for real work — a dozen reads, a few edits and a test run —
  /// and short enough that a loop is caught in minutes rather than in a bill.
  final int maxRounds;

  const AgentLoop({
    required this.workspace,
    required this.client,
    this.tools = kAgentTools,
    this.maxRounds = 25,
  });

  /// The instruction that makes the tools usable.
  ///
  /// It says the two things a model gets wrong without being told: that it
  /// cannot see the filesystem, and that it should verify rather than declare
  /// success. Both were learned the expensive way in v1's F-series, where a
  /// confident summary of work that had not happened was the most common
  /// failure people reported.
  static const systemPrompt = '''
You are working inside a code workspace. You cannot see the files unless you
read them — never assume a path exists, and never write a file from memory when
you could read it first.

Work in small steps. Read before you edit. Prefer edit_file over rewriting a
whole file. When you have finished, say what you changed in one or two
sentences, and do not claim anything you have not verified.''';

  Stream<AgentEvent> run({
    required String instruction,
    required ProviderAccess access,
    required String model,
  }) async* {
    final messages = <Map<String, dynamic>>[
      {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': instruction}
        ],
      },
    ];

    for (var round = 0; round < maxRounds; round++) {
      // Buffered rather than forwarded live: `round` is a Future, so a callback
      // cannot yield from this generator. The text arrives a beat later than it
      // could, which costs nothing next to a tool call taking seconds.
      final said = StringBuffer();
      final result = await client.round(
        access: access,
        model: model,
        messages: messages,
        tools: tools,
        system: systemPrompt,
        onText: said.write,
      );

      if (said.isNotEmpty) yield AgentSaid(said.toString());

      if (result.failure case final failure?) {
        yield AgentDone(reason: failure, detail: result.failureDetail);
        return;
      }

      if (!result.wantsTools) {
        yield const AgentDone();
        return;
      }

      messages.add(result.assistantMessage);

      // Sequentially, not concurrently. Two edits to one file in parallel is a
      // lost write, and the ordering is what the person reviewing the run reads
      // afterwards.
      final results = <Map<String, dynamic>>[];
      for (final call in result.calls) {
        yield AgentUsing(call.name, call.input);

        final outcome = await runTool(workspace, call.name, call.input);
        yield AgentUsed(
          call.name,
          outcome.text,
          isError: outcome.isError,
          changedPath: outcome.changedPath,
        );

        results.add({
          'type': 'tool_result',
          'tool_use_id': call.id,
          'content': outcome.text,
          if (outcome.isError) 'is_error': true,
        });
      }

      messages.add({'role': 'user', 'content': results});
    }

    yield AgentDone(
      reason: 'Stopped after $maxRounds rounds without finishing. What it did '
          'so far is above.',
    );
  }
}
