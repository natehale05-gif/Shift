import 'package:flutter/material.dart';

import '../../agents/diff.dart';
import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';

/// One hunk of a diff.
///
/// Added lines on a green ground, removed on a red one, both at low alpha:
/// Code mode's surface is near-black, and a solid fill behind mono text at the
/// weights this app uses makes the text harder to read than the tint is worth.
///
/// **Scrolls sideways in its own container.** A long line is normal in code and
/// must not make the whole screen scroll horizontally, which is the fastest way
/// to make a phone layout feel broken.
class HunkView extends StatelessWidget {
  final Hunk hunk;

  /// Shown above the lines. Off for the inline version in a transcript, where
  /// the surrounding rows already say which file this is.
  final bool showHeader;

  const HunkView({super.key, required this.hunk, this.showHeader = true});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final mono = text.bodySmall?.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['monospace'],
      height: 1.45,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showHeader)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.xxs),
            child: Text(hunk.header,
                style: mono?.copyWith(color: c.textFaint)),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            // At least the full width, so the tinted grounds run edge to edge
            // rather than stopping at the end of the shortest line.
            constraints: BoxConstraints(
              minWidth: MediaQuery.sizeOf(context).width - Space.lg * 3,
            ),
            // `stretch` inside a horizontal scroll view means "as wide as the
            // available width", and here that width is infinite. `IntrinsicWidth`
            // gives the column the width of its longest line first, so stretch
            // then means "as wide as the widest line" — which is what makes
            // every row's tint reach the same right edge.
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final line in hunk.lines) _Line(line: line, style: mono),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  final DiffLine line;
  final TextStyle? style;

  const _Line({required this.line, this.style});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    final (ground, ink) = switch (line.kind) {
      LineKind.added => (c.success.withValues(alpha: 0.14), c.text),
      LineKind.removed => (c.danger.withValues(alpha: 0.14), c.text),
      LineKind.kept => (Colors.transparent, c.textMuted),
    };

    return ColoredBox(
      color: ground,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        child: Text(
          // The marker column, which is what makes a diff readable when the
          // colours are not — printed, copied into a message, or colour-blind.
          switch (line.kind) {
            LineKind.added => '+ ${line.text}',
            LineKind.removed => '- ${line.text}',
            LineKind.kept => '  ${line.text}',
          },
          maxLines: 1,
          softWrap: false,
          style: style?.copyWith(color: ink),
        ),
      ),
    );
  }
}
