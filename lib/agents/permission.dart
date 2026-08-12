/// What an agent may do without being asked.
///
/// Pure, and deliberately the only place this is decided. Work mode points an
/// agent with a shell at a folder of somebody's own documents, which is only
/// defensible if what it may do without asking is a thing they chose and can
/// see. That makes this the safety-relevant file in the mode, so it holds no
/// state, touches no disk, and is decided entirely by its arguments.
library;

/// How much the person has agreed to in advance.
///
/// Named for what they mean rather than for how strict they are: "accept
/// edits" says which thing it accepts, where "medium" would leave everyone
/// guessing.
enum PermissionMode {
  /// Ask before anything that changes or runs. The default, and what someone
  /// who has just pointed this at their documents folder should get.
  ask,

  /// Writing and editing go through; a command still asks. The common working
  /// mode once you trust the job but not a shell.
  acceptEdits,

  /// Nothing is asked. For a folder whose contents are disposable, or a job
  /// already watched through once.
  dontAsk;

  String get label => switch (this) {
        PermissionMode.ask => 'Ask every time',
        PermissionMode.acceptEdits => 'Accept edits, ask before commands',
        PermissionMode.dontAsk => "Don't ask",
      };

  String get blurb => switch (this) {
        PermissionMode.ask =>
          'Nothing is written or run until you say so.',
        PermissionMode.acceptEdits =>
          'It edits files freely. Commands still stop and wait.',
        PermissionMode.dontAsk =>
          'It works without stopping. Everything it does is in this folder.',
      };

  static PermissionMode fromName(String? name) =>
      PermissionMode.values.firstWhere(
        (m) => m.name == name,
        // An unreadable value reads as the careful one. Defaulting the other
        // way would let a corrupt setting silently hand over a shell.
        orElse: () => PermissionMode.ask,
      );
}

/// What should happen before a call runs.
sealed class Decision {
  const Decision();
}

/// Go ahead.
class Allowed extends Decision {
  const Allowed();
}

/// Stop and put it to the person, in these words.
///
/// The sentence is built here rather than in the widget so that "what was
/// approved" and "what was shown" cannot drift — a prompt that says less than
/// the call does is worse than no prompt.
class NeedsApproval extends Decision {
  final String question;

  const NeedsApproval(this.question);
}

/// Never, and not as a question.
///
/// Distinct from [NeedsApproval] because there is nothing to weigh: a path
/// outside the workspace is not a judgement call, and offering it as one would
/// let somebody approve their way out of containment.
class Refused extends Decision {
  final String reason;

  const Refused(this.reason);
}

/// Tools that only look. Always allowed, under every mode.
///
/// Asking about these is worse than not asking: it is most of the prompts
/// somebody would see, none of them consequential, and it teaches the habit of
/// approving without reading — which is exactly the habit that makes the
/// consequential prompt useless.
const _readOnly = {'read_file', 'glob', 'grep', 'plan', 'ask'};

/// Whether [path] stays inside the workspace.
///
/// A second opinion, not the enforcement: [AgentWorkspace] refuses an escaping
/// path at the boundary and that is what actually protects the folder. This
/// exists so the *prompt* is never the thing that would have let it through —
/// an approval for `../../.ssh/id_rsa` should not be offerable in the first
/// place, even though granting it would still fail.
bool _inside(String path) {
  if (path.isEmpty) return true;
  if (path.startsWith('/') || path.startsWith(r'\')) return false;
  if (RegExp(r'^[A-Za-z]:').hasMatch(path)) return false;
  for (final part in path.split(RegExp(r'[/\\]'))) {
    if (part == '..') return false;
  }
  return true;
}

/// What should happen before [tool] runs with [input].
Decision decide(
  PermissionMode mode,
  String tool,
  Map<String, dynamic> input,
) {
  final path = '${input['path'] ?? ''}';
  if (path.isNotEmpty && !_inside(path)) {
    return Refused('$path is outside this folder.');
  }

  if (_readOnly.contains(tool)) return const Allowed();

  if (tool == 'run') {
    // Under `acceptEdits` too, and the name is the argument: it accepts
    // *edits*. A shell is not an edit, and a mode that quietly included one
    // would be the most expensive kind of surprise.
    if (mode == PermissionMode.dontAsk) return const Allowed();
    final command = [
      '${input['command'] ?? ''}',
      for (final a in input['args'] as List<dynamic>? ?? const []) '$a',
    ].where((p) => p.isNotEmpty).join(' ');
    return NeedsApproval(
      command.isEmpty ? 'Run a command?' : 'Run `$command`?',
    );
  }

  // Everything left changes a file.
  if (mode != PermissionMode.ask) return const Allowed();
  return NeedsApproval(
    // The path, not the tool. "Allow write_file?" is not a question anybody
    // can answer, and the file is the whole of what is at stake.
    //
    // Everything that is not an edit is a write, including `write_document`
    // and anything added later: naming the tools that mean "write" would make
    // a new one fall through to whichever wording came last.
    path.isEmpty
        ? 'Change a file?'
        : tool == 'edit_file'
            ? 'Edit $path?'
            : 'Write $path?',
  );
}
