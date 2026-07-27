
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/stores/conversation_store.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
class FollowUpChips extends StatelessWidget {
  const FollowUpChips({super.key});

  static const _suggestions = [
    'Explain that more simply',
    'Give me an example',
    'What are the next steps?',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final suggestion in _suggestions)
          ActionChip(
            label: Text(suggestion),
            labelStyle: theme.textTheme.labelSmall,
            side: BorderSide(color: colors.border),
            backgroundColor: Colors.transparent,
            visualDensity: VisualDensity.compact,
            onPressed: () =>
                context.read<ConversationStore>().sendMessage(suggestion),
          ),
      ],
    );
  }
}

/// Renders an interactive artifact (recipe/quiz/flashcards/checklist) live
/// inline in the conversation — a real widget in the chat, not a link to
/// another page.
