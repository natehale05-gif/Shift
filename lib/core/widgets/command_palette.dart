import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/stores/conversation_store.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

class _PaletteAction {
  final IconData icon;
  final String label;
  final VoidCallback run;

  const _PaletteAction({
    required this.icon,
    required this.label,
    required this.run,
  });
}

/// Cmd/Ctrl+K command palette: fuzzy chat search plus app actions, in a
/// centered dialog. Enter runs the first result.
Future<void> showCommandPalette(
  BuildContext context, {
  required void Function(int index) onNavigate,
}) {
  final store = context.read<ConversationStore>();
  return showDialog(
    context: context,
    barrierColor: Colors.black26,
    builder: (dialogContext) => Dialog(
      alignment: const Alignment(0, -0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: _PaletteBody(
          store: store,
          onNavigate: (index) {
            Navigator.of(dialogContext).pop();
            onNavigate(index);
          },
          onSelectConversation: (id) {
            Navigator.of(dialogContext).pop();
            onNavigate(0);
            store.selectConversation(id);
          },
          onNewChat: () {
            Navigator.of(dialogContext).pop();
            onNavigate(0);
            store.startNewConversation();
          },
        ),
      ),
    ),
  );
}

class _PaletteBody extends StatefulWidget {
  final ConversationStore store;
  final void Function(int index) onNavigate;
  final void Function(String conversationId) onSelectConversation;
  final VoidCallback onNewChat;

  const _PaletteBody({
    required this.store,
    required this.onNavigate,
    required this.onSelectConversation,
    required this.onNewChat,
  });

  @override
  State<_PaletteBody> createState() => _PaletteBodyState();
}

class _PaletteBodyState extends State<_PaletteBody> {
  String _query = '';

  List<_PaletteAction> get _actions {
    final all = [
      _PaletteAction(
        icon: Icons.add_comment_outlined,
        label: 'New chat',
        run: widget.onNewChat,
      ),
      _PaletteAction(
        icon: Icons.chat_bubble_outline_rounded,
        label: 'Go to Chat',
        run: () => widget.onNavigate(0),
      ),
      _PaletteAction(
        icon: Icons.workspace_premium_outlined,
        label: 'Go to Membership',
        run: () => widget.onNavigate(1),
      ),
      _PaletteAction(
        icon: Icons.groups_outlined,
        label: 'Go to Culture',
        run: () => widget.onNavigate(2),
      ),
      _PaletteAction(
        icon: Icons.settings_outlined,
        label: 'Go to Settings',
        run: () => widget.onNavigate(3),
      ),
    ];
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all.where((a) => a.label.toLowerCase().contains(q)).toList();
  }

  void _runFirst() {
    final actions = _actions;
    final conversations = widget.store.search(_query).take(8).toList();
    if (actions.isNotEmpty) {
      actions.first.run();
    } else if (conversations.isNotEmpty) {
      widget.onSelectConversation(conversations.first.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final actions = _actions;
    final conversations = widget.store.search(_query).take(8).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: TextField(
            autofocus: true,
            onChanged: (value) => setState(() => _query = value),
            onSubmitted: (_) => _runFirst(),
            decoration: const InputDecoration(
              hintText: 'Search chats or type a command…',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
            ),
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            children: [
              for (final action in actions)
                ListTile(
                  dense: true,
                  leading:
                      Icon(action.icon, size: 18, color: colors.textSecondary),
                  title: Text(action.label,
                      style: theme.textTheme.bodyMedium),
                  onTap: action.run,
                ),
              if (conversations.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: Text('Chats', style: theme.textTheme.labelSmall),
                ),
                for (final conversation in conversations)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      conversation.starred
                          ? Icons.star_rounded
                          : Icons.chat_bubble_outline_rounded,
                      size: 18,
                      color: conversation.starred
                          ? theme.colorScheme.primary
                          : colors.textSecondary,
                    ),
                    title: Text(
                      conversation.title,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () =>
                        widget.onSelectConversation(conversation.id),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
