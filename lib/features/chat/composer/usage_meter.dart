


import '../../../core/theme/app_theme.dart';
import '../../../data/stores/usage_store.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


/// Claude-style composer: a single rounded card holding the text field with
/// a row of controls beneath it — an attach button, a model chip, and a
/// circular purple send button.
class UsageMeter extends StatelessWidget {
  const UsageMeter({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final usage = context.watch<UsageStore>();
    return Tooltip(
      message: 'Illustrative daily limit — resets tomorrow. Nothing is '
          'metered or charged in this demo.',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: usage.fraction,
                minHeight: 4,
                backgroundColor: colors.border,
                color: usage.remaining == 0
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${usage.used}/${usage.cap} today',
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Claude-style tools/plus menu: per-turn toggles for web search, deep
/// research, code execution, and extended thinking. Each toggle feeds the
/// turn's [ChatOptions] and drives real behavior in both modes.
