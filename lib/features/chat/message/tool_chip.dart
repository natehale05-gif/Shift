
import 'package:flutter/material.dart';

import '../../../data/models/message_block.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
class ToolChip extends StatelessWidget {
  final ToolUseBlock block;

  const ToolChip({super.key, required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final running = block.status == ToolUseStatus.running;
    final failed = block.status == ToolUseStatus.failed;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: theme.colorScheme.primary,
              ),
            )
          else
            Icon(
              failed ? Icons.error_outline_rounded : Icons.check_rounded,
              size: 14,
              color: failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              block.detail != null && !running
                  ? '${block.label}  ·  ${block.detail}'
                  : block.label,
              style: theme.textTheme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
