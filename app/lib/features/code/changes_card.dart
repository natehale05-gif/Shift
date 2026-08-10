import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';

/// The files a run touched.
///
/// **Paths, and no per-file line counts.** The reference shows `+327 -0` beside
/// each row, and those numbers need a real diff of the file before against the
/// file after — which is the next wave's work. Printing a plausible number here
/// would be inventing the one figure a person would trust without checking, so
/// this shows what is genuinely known: which files, and how many.
class ChangesCard extends StatefulWidget {
  final List<String> paths;

  const ChangesCard({super.key, required this.paths});

  /// How many rows before the rest collapse behind a "more" line. Enough to see
  /// the shape of a change without the card becoming the screen.
  static const int visible = 5;

  @override
  State<ChangesCard> createState() => _ChangesCardState();
}

class _ChangesCardState extends State<ChangesCard> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    if (widget.paths.isEmpty) return const SizedBox.shrink();

    final shown = _all || widget.paths.length <= ChangesCard.visible
        ? widget.paths
        : widget.paths.take(ChangesCard.visible).toList();
    final hidden = widget.paths.length - shown.length;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: Space.md),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: 'Changes',
                style: text.titleSmall?.copyWith(color: c.text),
              ),
              // The count follows the label on the same line in a lighter grey,
              // never as a badge — a badge here reads as an alert.
              TextSpan(
                text: '  ${widget.paths.length}',
                style: text.titleSmall?.copyWith(color: c.textFaint),
              ),
            ]),
          ),
          const SizedBox(height: Space.xs),
          for (final path in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxs),
              child: Text(
                path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyMedium?.copyWith(
                  color: c.textMuted,
                  fontFamily: 'monospace',
                  fontFamilyFallback: const ['monospace'],
                ),
              ),
            ),
          if (hidden > 0)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _all = true),
                child: SizedBox(
                  height: kMinTouchTarget,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('··· $hidden more',
                        style: text.bodyMedium?.copyWith(color: c.textFaint)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
