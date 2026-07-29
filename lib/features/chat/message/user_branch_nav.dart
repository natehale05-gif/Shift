
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/stores/conversation_store.dart';
import '../../../core/theme/app_theme.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
import 'action_icon.dart';

class UserBranchNav extends StatelessWidget {
  final String anchorId;
  final int active;
  final int count;

  const UserBranchNav({super.key, 
    required this.anchorId,
    required this.active,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final store = context.read<ConversationStore>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ActionIcon(
            tooltip: 'Previous version',
            icon: Icons.chevron_left_rounded,
            onPressed:
                active > 0 ? () => store.switchBranch(anchorId, active - 1) : null,
          ),
          Text('${active + 1}/$count',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colors.textSecondary)),
          ActionIcon(
            tooltip: 'Next version',
            icon: Icons.chevron_right_rounded,
            onPressed: active < count - 1
                ? () => store.switchBranch(anchorId, active + 1)
                : null,
          ),
        ],
      ),
    );
  }
}
