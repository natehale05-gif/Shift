import 'package:flutter/material.dart';
import 'package:gpt_markdown/gpt_markdown.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/design/typography.dart';

/// A reply, rendered.
///
/// **The requirement that picked the renderer is partial input.** Every frame
/// during streaming is malformed markdown by definition — an unclosed fence, a
/// table with one row, a bare `**` waiting for its pair. A renderer that
/// throws, blanks, or reflows violently on those is unusable here however well
/// it handles a finished document. `gpt_markdown` is built for exactly this
/// case; the tests below drive it with half-written input and assert the text
/// is still on screen.
///
/// Styling comes from the app's own tokens rather than the package's
/// defaults: prose in the serif, code in the mono face on a sunken ground,
/// links in the accent. Left to itself the package would paint Material
/// defaults into the middle of a Claude-shaped app.
class MarkdownView extends StatelessWidget {
  final String source;

  const MarkdownView(this.source, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return SelectionArea(
      child: GptMarkdown(
        source,
        style: ShiftType.proseStyle(c.text),
        // Links take the accent through a builder rather than a colour
        // parameter — the package has no `linkColor`, which is the kind of
        // thing that only surfaces by compiling against it.
        linkBuilder: (context, label, uri, style) => Text.rich(
          label,
          style: style.copyWith(
            color: c.accent,
            decoration: TextDecoration.underline,
            decorationColor: c.accent,
          ),
        ),

        // A fenced block. The label is the language when the model gave one,
        // which is worth showing: it is how a reader knows whether they are
        // looking at the thing they asked for.
        codeBuilder: (context, name, code, closed) => Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: Space.sm),
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (name.isNotEmpty) ...[
                Text(name,
                    style: text.labelSmall?.copyWith(color: c.textFaint)),
                const SizedBox(height: Space.xs),
              ],
              // `closed` is false while the fence is still arriving. Rendering
              // it anyway — rather than withholding until it closes — is what
              // makes a long code reply feel like it is being written instead
              // of hanging.
              SelectableText(code, style: ShiftType.codeStyle(c.text)),
            ],
          ),
        ),

        // Inline `code`.
        highlightBuilder: (context, code, style) => Container(
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: BorderRadius.circular(Radii.xs),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Text(code, style: ShiftType.codeStyle(c.text, size: 14)),
        ),
      ),
    );
  }
}
