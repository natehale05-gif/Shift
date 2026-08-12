import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';

/// The one thing on screen that the job is waiting on.
///
/// Deliberately loud — accent border, two full-size buttons — because it is the
/// only moment in a run where nothing happens until somebody looks. A quiet
/// inline prompt here is a job that appears to have stalled.
///
/// **Allow is not the primary button.** Both are the same weight, and Don't
/// allow comes first in reading order, because a dialog that trains you to
/// press the emphasised one is a dialog that has stopped asking anything.
class ApprovalCard extends StatelessWidget {
  final String question;
  final VoidCallback onAllow;
  final VoidCallback onDeny;

  const ApprovalCard({
    super.key,
    required this.question,
    required this.onAllow,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
      decoration: BoxDecoration(
        color: c.accentWash,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.accent),
      ),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(Icons.pan_tool_outlined, size: 16, color: c.accent),
              ),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  question,
                  style: text.bodyLarge?.copyWith(color: c.text),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          // Wrapped, not a Row: two buttons and a long command name overflow a
          // phone, and an approval whose buttons are off the edge of the screen
          // is a job nobody can unblock.
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              _Choice(label: "Don't allow", onTap: onDeny, filled: false),
              _Choice(label: 'Allow', onTap: onAllow, filled: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool filled;

  const _Choice({
    required this.label,
    required this.onTap,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Material(
      color: filled ? c.accent : c.surface,
      borderRadius: BorderRadius.circular(Radii.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: kMinTouchTarget,
            minWidth: 120,
          ),
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: filled ? c.onAccent : c.text,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ),
    );
  }
}
