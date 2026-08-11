import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import 'run_changes.dart';

/// The files a run changed, with what it did to each.
///
/// The numbers are real: a line diff of the file as it is now against the file
/// as it was before the run first touched it. An earlier version of this card
/// listed paths and no counts, because the counts had nowhere to come from —
/// printing a plausible number would have invented the one figure a person
/// trusts without checking.
class ChangesCard extends StatefulWidget {
  final List<FileChange> changes;

  /// Null while they are still being read off disk.
  final bool loading;

  final void Function(String path)? onOpen;

  const ChangesCard({
    super.key,
    required this.changes,
    this.loading = false,
    this.onOpen,
  });

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
    if (widget.changes.isEmpty) return const SizedBox.shrink();

    final shown = _all || widget.changes.length <= ChangesCard.visible
        ? widget.changes
        : widget.changes.take(ChangesCard.visible).toList();
    final hidden = widget.changes.length - shown.length;

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
                text: '  ${widget.changes.length}',
                style: text.titleSmall?.copyWith(color: c.textFaint),
              ),
            ]),
          ),
          const SizedBox(height: Space.xs),
          for (final change in shown)
            _Row(change: change, onOpen: widget.onOpen),
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

class _Row extends StatelessWidget {
  final FileChange change;
  final void Function(String path)? onOpen;

  const _Row({required this.change, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen == null ? null : () => onOpen!(change.path),
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  change.path,
                  maxLines: 1,
                  // The end of a path is the part that identifies it, so a long
                  // one loses its directories rather than its filename.
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: c.textMuted,
                    fontFamily: 'monospace',
                    fontFamilyFallback: const ['monospace'],
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              Text(
                '${change.stat}',
                style: text.bodySmall?.copyWith(color: c.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
