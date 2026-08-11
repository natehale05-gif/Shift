import 'dart:convert';

import 'workspace.dart';

/// Everything an agent can do, as a closed set.
///
/// Sealed for the reason everything in this codebase is sealed: adding a tool
/// becomes a compile error at every place that has to learn about it — the
/// executor, the schema sent to the model, and the row that renders it — rather
/// than something three of the four remember.
///
/// **Deliberately small.** Read, write, edit, find, and run. Everything a
/// coding agent does is a composition of those, and each one added past them is
/// another shape the review UI has to render and another thing to get wrong.
sealed class AgentTool {
  const AgentTool();

  /// The name the model calls it by.
  String get name;

  /// What the model is told it does. Written for the model, which means saying
  /// the constraint out loud: it cannot see the filesystem and will invent
  /// paths unless told to look first.
  String get description;

  /// JSON Schema for the arguments.
  Map<String, dynamic> get schema;
}

class ReadFile extends AgentTool {
  const ReadFile();

  @override
  String get name => 'read_file';

  @override
  String get description =>
      'Read a text file. Paths are relative to the workspace root. Read a '
      'file before editing it — you cannot see its contents otherwise.';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'path': {'type': 'string', 'description': 'Relative path.'},
        },
        'required': ['path'],
      };
}

class WriteFile extends AgentTool {
  const WriteFile();

  @override
  String get name => 'write_file';

  @override
  String get description =>
      'Create a file, or replace one entirely. Parent directories are created. '
      'To change part of a file, prefer edit_file — writing a whole file from '
      'memory loses anything you did not read.';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'contents': {'type': 'string'},
        },
        'required': ['path', 'contents'],
      };
}

class EditFile extends AgentTool {
  const EditFile();

  @override
  String get name => 'edit_file';

  @override
  String get description =>
      'Replace an exact string in a file. The old string must appear exactly '
      'once — include surrounding lines to make it unique. This fails rather '
      'than guessing which occurrence you meant.';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'path': {'type': 'string'},
          'old': {'type': 'string', 'description': 'Exact text to replace.'},
          'new': {'type': 'string'},
        },
        'required': ['path', 'old', 'new'],
      };
}

class GlobFiles extends AgentTool {
  const GlobFiles();

  @override
  String get name => 'glob';

  @override
  String get description =>
      'List files matching a glob, e.g. `**/*.dart`. Use this to find out what '
      'exists before assuming a path.';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'pattern': {'type': 'string'},
        },
        'required': ['pattern'],
      };
}

class GrepFiles extends AgentTool {
  const GrepFiles();

  @override
  String get name => 'grep';

  @override
  String get description =>
      'Search file contents with a regular expression. Returns matching lines '
      'with their paths and line numbers.';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'pattern': {'type': 'string'},
          'in': {'type': 'string', 'description': 'Optional glob to narrow.'},
        },
        'required': ['pattern'],
      };
}

class RunCommand extends AgentTool {
  const RunCommand();

  @override
  String get name => 'run';

  @override
  String get description =>
      'Run a command in the workspace root. Give the executable and its '
      'arguments separately — there is no shell, so pipes and redirection do '
      'not work.';

  @override
  Map<String, dynamic> get schema => {
        'type': 'object',
        'properties': {
          'command': {'type': 'string'},
          'args': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'required': ['command'],
      };
}

/// Declaring what it is about to do, and keeping that list current.
///
/// The difference between a task list and a transcript: a transcript says what
/// happened, a plan says what is *going to*. Somebody watching an agent work
/// through their documents needs the second one — the first only tells them
/// where it got to after it got there.
class PlanTasks extends AgentTool {
  const PlanTasks();

  @override
  String get name => 'plan';

  @override
  String get description =>
      'Set or update the task list for this job. Call it once at the start '
      'with everything you intend to do, and again whenever something is '
      'finished or the plan changes. Keep it short — these are the steps a '
      'person would recognise, not every tool call.';

  @override
  Map<String, dynamic> get schema => const {
        'type': 'object',
        'properties': {
          'tasks': {
            'type': 'array',
            'items': {
              'type': 'object',
              'properties': {
                'title': {'type': 'string'},
                'done': {'type': 'boolean'},
              },
              'required': ['title'],
            },
          },
        },
        'required': ['tasks'],
      };
}

/// Stopping to put a decision back to the person.
///
/// Only for decisions that are genuinely theirs — which is why the description
/// says so twice. An agent that asks about everything is an agent nobody
/// leaves running, and the value of the mode is being able to walk away.
class AskPerson extends AgentTool {
  const AskPerson();

  @override
  String get name => 'ask';

  @override
  String get description =>
      'Stop and ask when a decision is genuinely the person\'s — a preference '
      'you cannot infer, a fact only they have, or a choice with consequences '
      'they would want to make. Do not use it for anything you could find out '
      'by reading a file, and do not use it to confirm work you have been '
      'asked to do.';

  @override
  Map<String, dynamic> get schema => const {
        'type': 'object',
        'properties': {
          'question': {'type': 'string'},
        },
        'required': ['question'],
      };
}

/// The set a coding agent is given.
const List<AgentTool> kAgentTools = [
  ReadFile(),
  WriteFile(),
  EditFile(),
  GlobFiles(),
  GrepFiles(),
  RunCommand(),
];

/// The set a work agent is given.
///
/// The same reach as the coding set — Work is pointed at a folder of somebody
/// else's documents, and the answer to "what may it do there" is a permission
/// mode they chose rather than a shorter tool list. See `permission.dart`.
///
/// Plus the two that make it a *work* agent rather than a coding agent with
/// different words: it says what it is going to do, and it stops when the
/// decision is not its to make.
const List<AgentTool> kWorkTools = [
  ReadFile(),
  WriteFile(),
  EditFile(),
  GlobFiles(),
  GrepFiles(),
  RunCommand(),
  PlanTasks(),
  AskPerson(),
];

/// What came back, as the model will read it.
class ToolResult {
  final String text;

  /// True when the tool could not do what was asked. The model is told either
  /// way — a failure it cannot see is a failure it will repeat.
  final bool isError;

  /// What changed on disk, if anything. Drives the diff the person reviews;
  /// the model never sees this.
  final String? changedPath;

  /// [changedPath]'s contents *before* this call, empty for a file that did not
  /// exist. The other half of a diff, and the only moment it can be had —
  /// afterwards the old version is gone.
  ///
  /// Never sent to the model. It is here because this is the one place in the
  /// program that holds both versions of a file.
  final String? previousContent;

  const ToolResult(
    this.text, {
    this.isError = false,
    this.changedPath,
    this.previousContent,
  });
}

/// Runs one tool call against a workspace.
///
/// Every failure comes back as a [ToolResult] rather than an exception,
/// including a path that tried to escape: the agent has to be *told* it was
/// refused so it can choose differently. Throwing would end the turn and leave
/// the person with a stack trace instead of a reply.
Future<ToolResult> runTool(
  AgentWorkspace workspace,
  String name,
  Map<String, dynamic> arguments,
) async {
  String arg(String key) => '${arguments[key] ?? ''}';

  try {
    switch (name) {
      case 'read_file':
        final text = await workspace.readText(arg('path'));
        // Truncated with a note rather than silently: a model given half a
        // file with no warning will edit against the half it saw.
        const limit = 60000;
        return text.length <= limit
            ? ToolResult(text)
            : ToolResult('${text.substring(0, limit)}\n\n'
                '[truncated — file is ${text.length} characters]');

      case 'write_file':
        // Read before writing, purely to keep the old version for the diff.
        // A `try` rather than an existence check: between the check and the
        // read the answer can change, and "it was not there" and "we could not
        // read it" both mean the same thing here — there is no before.
        String previous;
        try {
          previous = await workspace.readText(arg('path'));
        } catch (_) {
          previous = '';
        }
        await workspace.writeText(arg('path'), arg('contents'));
        return ToolResult(
          'Wrote ${arg('path')}.',
          changedPath: arg('path'),
          previousContent: previous,
        );

      case 'edit_file':
        final path = arg('path');
        final old = arg('old');
        final replacement = arg('new');
        final current = await workspace.readText(path);

        final occurrences = old.isEmpty ? 0 : _count(current, old);
        if (occurrences == 0) {
          return ToolResult(
            'That exact text is not in $path. Read the file and copy the '
            'text you mean, including its indentation.',
            isError: true,
          );
        }
        if (occurrences > 1) {
          // Refusing beats picking. An edit applied to the wrong one of four
          // identical lines is a bug that looks like the model working.
          return ToolResult(
            'That text appears $occurrences times in $path. Include enough '
            'surrounding lines to identify the one you mean.',
            isError: true,
          );
        }

        await workspace.writeText(path, current.replaceFirst(old, replacement));
        return ToolResult(
          'Edited $path.',
          changedPath: path,
          // Already in hand: the occurrence count needed it.
          previousContent: current,
        );

      case 'glob':
        final found = await workspace.glob(arg('pattern'));
        return ToolResult(found.isEmpty ? 'No files match.' : found.join('\n'));

      case 'grep':
        final hits = await workspace.grep(
          arg('pattern'),
          inGlob: arguments['in'] as String?,
        );
        return ToolResult(hits.isEmpty
            ? 'No matches.'
            : hits.map((h) => '${h.path}:${h.line}: ${h.text}').join('\n'));

      case 'run':
        final args = [
          for (final a in arguments['args'] as List<dynamic>? ?? const [])
            '$a',
        ];
        final result = await workspace.run(arg('command'), args);
        final out = [
          if (result.stdout.isNotEmpty) result.stdout,
          if (result.stderr.isNotEmpty) result.stderr,
        ].join('\n');
        if (result.timedOut) {
          return ToolResult('Timed out and was stopped.\n$out', isError: true);
        }
        return ToolResult(
          out.isEmpty ? 'Exit ${result.exitCode}.' : out,
          isError: !result.ok,
        );

      default:
        return ToolResult('No tool called "$name".', isError: true);
    }
  } on OutsideWorkspace catch (e) {
    return ToolResult('$e', isError: true);
  } catch (e) {
    return ToolResult('$name failed: $e', isError: true);
  }
}

int _count(String haystack, String needle) {
  var found = 0;
  var at = haystack.indexOf(needle);
  while (at != -1) {
    found++;
    at = haystack.indexOf(needle, at + needle.length);
  }
  return found;
}

/// The tool set, as a provider's `tools` array.
List<Map<String, dynamic>> toolSchemas(List<AgentTool> tools) => [
      for (final tool in tools)
        {
          'name': tool.name,
          'description': tool.description,
          'input_schema': tool.schema,
        },
    ];

/// For a fixture, and for logging a call in a form a person can read.
String describeCall(String name, Map<String, dynamic> arguments) =>
    '$name(${jsonEncode(arguments)})';
