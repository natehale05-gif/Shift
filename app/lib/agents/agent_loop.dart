import '../providers/access.dart';
import 'anthropic_agent.dart';
import 'permission.dart';
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

/// One step of the agent's own plan.
class AgentTask {
  final String title;
  final bool done;

  const AgentTask(this.title, {this.done = false});

  Map<String, dynamic> toJson() => {'title': title, 'done': done};

  static AgentTask? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final title = raw['title'];
    if (title is! String || title.isEmpty) return null;
    return AgentTask(title, done: raw['done'] == true);
  }
}

/// The agent said what it intends to do, or crossed something off.
///
/// The whole list every time rather than a delta: the model maintains it, and
/// reconciling partial updates from a model is how a task list ends up
/// disagreeing with itself.
class AgentPlanned extends AgentEvent {
  final List<AgentTask> tasks;

  const AgentPlanned(this.tasks);
}

/// It stopped to put a decision back to the person.
///
/// Terminal for the round: there is nothing useful to do with the rest of a
/// plan that depends on an answer nobody has given yet.
class AgentAsked extends AgentEvent {
  final String question;

  const AgentAsked(this.question);
}

/// It finished, with what the model was told.
class AgentUsed extends AgentEvent {
  final String tool;
  final String result;
  final bool isError;

  /// The file this touched, if any. What the diff review is built from.
  final String? changedPath;

  /// [changedPath] as it was before this call. Carried through because the
  /// moment after the write is too late to ask.
  final String? previousContent;

  const AgentUsed(
    this.tool,
    this.result, {
    this.isError = false,
    this.changedPath,
    this.previousContent,
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

  /// What this agent is told before the job.
  ///
  /// Injected rather than fixed because the loop is not about code: Work mode
  /// points the same machinery at a folder of documents, where the standing
  /// instructions are different in every line that matters. Defaults to
  /// [codeBrief], so nothing that already builds one changes.
  final String brief;

  /// Consulted before every call that could change or run something.
  ///
  /// A function rather than a mode, so the loop does not have to know what a
  /// permission mode is and a test can drive one decision at a time. Null
  /// means everything is allowed — which is Code mode's behaviour today, and
  /// stating it as a default keeps that a choice rather than an omission.
  final Decision Function(String tool, Map<String, dynamic> input)? permit;

  /// Puts an approval to the person and waits for the answer.
  ///
  /// Null means nobody can be asked, and a call needing approval is then
  /// refused rather than allowed — a gate with no way to ask is not a reason
  /// to go ahead.
  final Future<bool> Function(String question)? approve;

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
    this.brief = codeBrief,
    this.permit,
    this.approve,
    this.maxRounds = 25,
  });

  /// The instruction that makes the tools usable.
  ///
  /// It says the two things a model gets wrong without being told: that it
  /// cannot see the filesystem, and that it should verify rather than declare
  /// success. Both were learned the expensive way in v1's F-series, where a
  /// confident summary of work that had not happened was the most common
  /// failure people reported.
  static const codeBrief = '''
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
        system: brief,
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
      var asked = false;
      for (final call in result.calls) {
        // The two tools that are about the *run* rather than about the folder,
        // so they are answered here rather than in `runTool`, which knows only
        // how to touch a workspace.
        if (call.name == 'plan') {
          final tasks = [
            for (final t in call.input['tasks'] as List<dynamic>? ?? const [])
              ?AgentTask.fromJson(t),
          ];
          yield AgentPlanned(tasks);
          results.add(_toolResult(call.id, 'Noted.'));
          continue;
        }
        if (call.name == 'ask') {
          final question = '${call.input['question'] ?? ''}'.trim();
          if (question.isEmpty) {
            results.add(_toolResult(
              call.id,
              'A question needs wording. Say what you need to know.',
              isError: true,
            ));
            continue;
          }
          yield AgentAsked(question);
          asked = true;
          results.add(_toolResult(call.id, 'Asked.'));
          continue;
        }

        // Checked before the call, not after: an approval that arrives once
        // the file is already written is a notification.
        if (permit case final permit?) {
          final decision = permit(call.name, call.input);
          if (decision is Refused) {
            yield AgentUsed(call.name, decision.reason, isError: true);
            results.add(_toolResult(call.id, decision.reason, isError: true));
            continue;
          }
          if (decision is NeedsApproval) {
            final granted = await approve?.call(decision.question) ?? false;
            if (!granted) {
              const declined = 'The person declined that. Carry on with what '
                  'does not depend on it, or ask what to do instead.';
              yield AgentUsed(call.name, declined, isError: true);
              results.add(_toolResult(call.id, declined, isError: true));
              continue;
            }
          }
        }

        yield AgentUsing(call.name, call.input);

        final outcome = await runTool(workspace, call.name, call.input);
        yield AgentUsed(
          call.name,
          outcome.text,
          isError: outcome.isError,
          changedPath: outcome.changedPath,
          previousContent: outcome.previousContent,
        );

        results.add(
            _toolResult(call.id, outcome.text, isError: outcome.isError));
      }

      messages.add({'role': 'user', 'content': results});

      // After the results are recorded, so a follow-up resumes from a complete
      // transcript rather than from one missing the round that asked.
      if (asked) {
        yield const AgentDone();
        return;
      }
    }

    yield AgentDone(
      reason: 'Stopped after $maxRounds rounds without finishing. What it did '
          'so far is above.',
    );
  }

  static Map<String, dynamic> _toolResult(
    String id,
    String content, {
    bool isError = false,
  }) =>
      {
        'type': 'tool_result',
        'tool_use_id': id,
        'content': content,
        if (isError) 'is_error': true,
      };
}
