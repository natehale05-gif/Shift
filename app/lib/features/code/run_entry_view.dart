import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/agent_run.dart';

/// One entry of a transcript.
///
/// A dispatcher plus four small widgets rather than one build method with a
/// four-way `if`: each shape is genuinely different — the person's words are an
/// inset bubble, a tool call is a chip, an ending is a banner — and a switch
/// over a sealed type makes a fifth kind a compile error here.
class RunEntryView extends StatelessWidget {
  final RunEntry entry;

  const RunEntryView({super.key, required this.entry});

  @override
  Widget build(BuildContext context) => switch (entry) {
        RunAsked(:final text) => _Asked(text: text),
        RunSaid(:final text) => _Said(text: text),
        final RunTool tool => _Tool(entry: tool),
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

  const _Tool({required this.entry});

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
