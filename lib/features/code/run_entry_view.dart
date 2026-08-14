import 'package:flutter/material.dart';

import '../../agents/agent_loop.dart';
import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/agent_run.dart';
import 'hunk_view.dart';
import 'run_changes.dart';

/// One entry of a transcript.
///
/// A dispatcher plus four small widgets rather than one build method with a
/// four-way `if`: each shape is genuinely different — the person's words are an
/// inset bubble, a tool call is a chip, an ending is a banner — and a switch
/// over a sealed type makes a fifth kind a compile error here.
class RunEntryView extends StatelessWidget {
  final RunEntry entry;

  /// The diff to show under this row, when it is an edit and there is one.
  ///
  /// Passed in rather than computed here: the screen reads every changed file
  /// once, and a widget that went to disk on every rebuild would read them on
  /// every frame of a running agent.
  ///
  /// Attached to the **last** row that touched a given file, not to every one.
  /// The baseline is captured once per run rather than once per edit, so what
  /// exists is the file's whole change — showing it under all three of three
  /// edits would print the same diff three times and imply each edit did all
  /// of it.
  final FileChange? change;

  const RunEntryView({super.key, required this.entry, this.change});

  @override
  Widget build(BuildContext context) => switch (entry) {
        RunAsked(:final text) => _Asked(text: text),
        RunSaid(:final text) => _Said(text: text),
        final RunTool tool => _Tool(entry: tool, change: change),
        RunPlan(:final tasks) => _Plan(tasks: tasks),
        RunQuestion(:final question) => _Question(question: question),
        final RunEnded ended => _Ended(entry: ended),
      };
}

/// What the person asked for, as an inset bubble — the shape the reference
/// gives your own words, which is what separates them from the agent's at a
/// glance without a label saying "you".
class _Asked extends StatelessWidget {
  final String text;

  const _Asked({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        padding: const EdgeInsets.all(Space.md),
        child: SelectableText(
          text,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.text),
        ),
      ),
    );
  }
}

class _Said extends StatelessWidget {
  final String text;

  const _Said({required this.text});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: SelectableText(
        text,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.text),
      ),
    );
  }
}

/// A tool call: what it was, on what, and how it went.
///
/// The argument shown is the *subject* — a path, a pattern, a command — not the
/// whole JSON. A transcript is read to follow what happened, and a wall of
/// serialised arguments is the fastest way to make it unreadable. The full
/// result is behind a tap for when following is not enough.
class _Tool extends StatefulWidget {
  final RunTool entry;
  final FileChange? change;

  const _Tool({required this.entry, this.change});

  @override
  State<_Tool> createState() => _ToolState();
}

class _ToolState extends State<_Tool> {
  bool _open = false;

  /// The one argument worth putting on the line, per tool.
  static String subjectOf(RunTool entry) {
    final input = entry.input;
    final subject = switch (entry.tool) {
      'read_file' || 'write_file' || 'edit_file' => input['path'],
      'glob' || 'grep' => input['pattern'],
      'run' => [
          input['command'],
          for (final a in input['args'] as List<dynamic>? ?? const []) a,
        ].join(' '),
      _ => null,
    };
    return subject == null ? '' : '$subject';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final entry = widget.entry;
    final subject = subjectOf(entry);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xxs),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: entry.result == null
              ? null
              : () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Container(
            // A tool row is tappable — that is how its output is read — so it
            // is a thumb target, not a line of text that happens to respond.
            constraints: const BoxConstraints(minHeight: kMinTouchTarget),
            padding: const EdgeInsets.symmetric(
                vertical: Space.xs, horizontal: Space.xs),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Glyph(entry: entry),
                    const SizedBox(width: Space.xs),
                    Text(entry.tool,
                        style: text.bodyMedium?.copyWith(color: c.textMuted)),
                    if (subject.isNotEmpty) ...[
                      const SizedBox(width: Space.xs),
                      Expanded(
                        child: Text(
                          subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium?.copyWith(
                            color: entry.isError ? c.danger : c.text,
                            fontFamily: 'monospace',
                            fontFamilyFallback: const ['monospace'],
                          ),
                        ),
                      ),
                    ] else
                      const Spacer(),
                  ],
                ),
                // The diff where the edit happened, in the story of the run —
                // which is the half of a review people actually read.
                if (widget.change case final change?)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final hunk in change.hunks)
                          Padding(
                            padding: const EdgeInsets.only(bottom: Space.xs),
                            child: HunkView(hunk: hunk, showHeader: false),
                          ),
                      ],
                    ),
                  ),
                if (_open && entry.result != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs, left: 22),
                    child: SelectableText(
                      entry.result!,
                      style: text.bodySmall?.copyWith(
                        color: c.textMuted,
                        fontFamily: 'monospace',
                        fontFamilyFallback: const ['monospace'],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Glyph extends StatelessWidget {
  final RunTool entry;

  const _Glyph({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // Still running is a spinner rather than a static icon, because a `run`
    // that takes eight seconds has to read as happening rather than as stuck.
    if (entry.running) {
      return SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 1.6, color: c.textMuted),
      );
    }
    return Icon(
      entry.isError ? Icons.error_outline_rounded : Icons.check_rounded,
      size: 15,
      color: entry.isError ? c.danger : c.success,
    );
  }
}

/// The task list as it stood at this point in the run.
///
/// Rendered in the transcript rather than only as a live header, because the
/// list *changing* is part of what happened: a third task appearing halfway
/// through is the agent telling you what it found, and a view that only ever
/// showed the final version would hide that.
class _Plan extends StatelessWidget {
  final List<AgentTask> tasks;

  const _Plan({required this.tasks});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    // An empty plan is the agent saying nothing. Drawing an empty box for it
    // would put a hole in the transcript.
    if (tasks.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(Radii.md),
        ),
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final task in tasks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        task.done
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        size: 15,
                        color: task.done ? c.success : c.textFaint,
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Expanded(
                      child: Text(
                        task.title,
                        style: text.bodyMedium?.copyWith(
                          // Finished work stays readable rather than being
                          // struck through: it is the record of what was done,
                          // not something to skip over.
                          color: task.done ? c.textMuted : c.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// It stopped and put a question to the person.
///
/// Given the accent rather than the danger colour: being asked something is
/// the agent working correctly, and dressing it as a failure would teach people
/// to dread the one thing that keeps a decision theirs.
class _Question extends StatelessWidget {
  final String question;

  const _Question({required this.question});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.accentWash,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.accent.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(Space.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.help_outline_rounded, size: 16, color: c.accent),
            ),
            const SizedBox(width: Space.xs),
            Expanded(
              child: SelectableText(
                question,
                style: text.bodyLarge?.copyWith(color: c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Why it stopped, when that is worth saying.
///
/// A clean finish renders nothing: the transcript ending *is* the ending, and a
/// banner announcing that nothing went wrong is noise on every successful run.
class _Ended extends StatelessWidget {
  final RunEnded entry;

  const _Ended({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    if (entry.ok) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.danger.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.reason!,
                style: text.bodyMedium?.copyWith(color: c.text)),
            if (entry.detail case final detail?) ...[
              const SizedBox(height: Space.xs),
              SelectableText(
                detail,
                style: text.bodySmall?.copyWith(
                  color: c.textFaint,
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['monospace'],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
