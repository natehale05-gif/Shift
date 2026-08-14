import '../agents/agent_loop.dart';

/// What an agent did, in the order it did it.
///
/// The transcript is the product of this mode. A row in a list tells you an
/// agent finished; this is the only place that says *what it looked at*, *what
/// it changed*, and *why it stopped* — which is what a person actually reviews.
///
/// Sealed for the reason everything here is sealed: a new kind of entry becomes
/// a compile error at the screen that renders it and the store that writes it,
/// rather than something one of the two quietly drops.
sealed class RunEntry {
  const RunEntry();

  Map<String, dynamic> toJson();

  static RunEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    return switch (raw['kind']) {
      'asked' => RunAsked('${raw['text']}'),
      'said' => RunSaid('${raw['text']}'),
      'tool' => RunTool(
          tool: '${raw['tool']}',
          input: raw['input'] is Map
              ? Map<String, dynamic>.from(raw['input'] as Map)
              : const {},
        )
        ..result = raw['result'] as String?
        ..isError = raw['isError'] == true
        ..changedPath = raw['changedPath'] as String?,
      'plan' => RunPlan([
          for (final t in raw['tasks'] as List<dynamic>? ?? const [])
            ?AgentTask.fromJson(t),
        ]),
      'question' => RunQuestion('${raw['text']}'),
      'ended' =>
        RunEnded(reason: raw['reason'] as String?, detail: raw['detail'] as String?),
      _ => null,
    };
  }
}

/// The person: the task that started the run, or a follow-up.
class RunAsked extends RunEntry {
  final String text;

  const RunAsked(this.text);

  @override
  Map<String, dynamic> toJson() => {'kind': 'asked', 'text': text};
}

/// The agent, reasoning between tool calls.
class RunSaid extends RunEntry {
  final String text;

  const RunSaid(this.text);

  @override
  Map<String, dynamic> toJson() => {'kind': 'said', 'text': text};
}

/// A tool call.
///
/// **Mutated in place when it finishes**, rather than a second entry, because a
/// call is announced before it runs — a `run` that takes eight seconds has to
/// read as happening — and two entries would put the same call in the
/// transcript twice.
class RunTool extends RunEntry {
  final String tool;
  final Map<String, dynamic> input;

  /// What the model was told. Null while it is still running.
  String? result;

  bool isError = false;

  /// The file this touched, if any. What the Changes list is built from.
  String? changedPath;

  RunTool({required this.tool, required this.input});

  bool get running => result == null;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'tool',
        'tool': tool,
        'input': input,
        // A call that was still running when this was written did not finish,
        // and storing it as finished-with-no-output would present an
        // interrupted run as a completed one.
        if (result != null) 'result': result,
        if (isError) 'isError': true,
        if (changedPath != null) 'changedPath': changedPath,
      };
}

/// The run stopped.
/// The agent's own task list, as it stood at this point in the run.
///
/// An entry rather than a field on the run, for the same reason everything
/// else here is one: the list changing *is* something that happened, and a
/// transcript that only kept the final version could not show that the third
/// task appeared halfway through because of what the second one found.
class RunPlan extends RunEntry {
  final List<AgentTask> tasks;

  const RunPlan(this.tasks);

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'plan',
        'tasks': [for (final t in tasks) t.toJson()],
      };
}

/// It stopped and put a question to the person.
class RunQuestion extends RunEntry {
  final String question;

  const RunQuestion(this.question);

  @override
  Map<String, dynamic> toJson() => {'kind': 'question', 'text': question};
}

class RunEnded extends RunEntry {
  /// Set when it stopped for a reason worth saying — a failure, or the round
  /// limit. Null when it simply finished.
  final String? reason;

  /// The technical fact behind [reason], for a bug report.
  final String? detail;

  const RunEnded({this.reason, this.detail});

  bool get ok => reason == null;

  @override
  Map<String, dynamic> toJson() => {
        'kind': 'ended',
        if (reason != null) 'reason': reason,
        if (detail != null) 'detail': detail,
      };
}

/// One agent's whole transcript.
class AgentRun {
  final String agentId;
  final List<RunEntry> entries;

  /// Each touched file as it was **before this run first touched it**.
  ///
  /// First touch wins, deliberately. Recording the content before every write
  /// would mean the second edit to a file diffs against the first edit's
  /// output, and the run would appear to have done less than it did.
  ///
  /// Kept beside the entries rather than inside them, and stored under its own
  /// key: these are whole files, and the list screens decode transcripts
  /// constantly.
  final Map<String, String> baseline;

  AgentRun({
    required this.agentId,
    List<RunEntry>? entries,
    Map<String, String>? baseline,
  })  : entries = entries ?? [],
        baseline = baseline ?? {};

  /// Every file the run touched, in the order it first touched them.
  ///
  /// Derived rather than stored: the entries are the record, and a second copy
  /// of the same fact is a second thing that can be wrong.
  List<String> get changedPaths {
    final seen = <String>[];
    for (final entry in entries) {
      if (entry is! RunTool) continue;
      if (entry.changedPath case final path? when !seen.contains(path)) {
        seen.add(path);
      }
    }
    return List.unmodifiable(seen);
  }

  List<Map<String, dynamic>> toJson() => [for (final e in entries) e.toJson()];

  static AgentRun fromJson(
    String agentId,
    Object? raw, {
    Map<String, String>? baseline,
  }) =>
      AgentRun(
        agentId: agentId,
        entries: [
          for (final entry in raw is List ? raw : const []) ?RunEntry.fromJson(entry),
        ],
        baseline: baseline,
      );
}
