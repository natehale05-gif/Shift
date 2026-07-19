import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/conversation.dart';
import '../../state/conversation_store.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

class ConversationSidebar extends StatelessWidget {
  const ConversationSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ConversationStore>();
    final colors = Theme.of(context).extension<AppSemanticColors>()!;

    return Container(
      width: 260,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: FilledButton.tonalIcon(
              onPressed: () => store.startNewConversation(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('New chat'),
            ),
          ),
          Expanded(
            child: store.conversations.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      'Your conversations will show up here.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  )
                : ListView.builder(
                    itemCount: store.conversations.length,
                    itemBuilder: (context, index) {
                      final convo = store.conversations[index];
                      final isSelected = convo.id == store.current?.id;
                      return _ConversationTile(
                        conversation: convo,
                        selected: isSelected,
                        onTap: () => store.selectConversation(convo.id),
                        onDelete: () => store.deleteConversation(convo.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.conversation,
    required this.selected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5) : null,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
        dense: true,
        title: Text(
          conversation.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium,
        ),
        onTap: onTap,
        trailing: IconButton(
          icon: const Icon(Icons.close_rounded, size: 16),
          tooltip: 'Delete',
          onPressed: onDelete,
        ),
      ),
    );
  }
}
