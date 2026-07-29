
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/chat_message.dart';
import '../../../data/stores/conversation_store.dart';
import '../../../core/theme/app_theme.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
import 'action_icon.dart';

class VariantNavigator extends StatelessWidget {
  final ChatMessage message;

  const VariantNavigator({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final store = context.read<ConversationStore>();
    final index = message.activeVariant;
    final count = message.variantCount;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ActionIcon(
          tooltip: 'Previous response',
          icon: Icons.chevron_left_rounded,
          onPressed:
              index > 0 ? () => store.selectVariant(message.id, index - 1) : null,
        ),
        Text(
          '${index + 1}/$count',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: colors.textSecondary),
        ),
        ActionIcon(
          tooltip: 'Next response',
          icon: Icons.chevron_right_rounded,
          onPressed: index < count - 1
              ? () => store.selectVariant(message.id, index + 1)
              : null,
        ),
      ],
    );
  }
}
