import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/studio_type.dart';
import '../../state/conversation_store.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/conversation_sidebar.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/common/glass_app_bar.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSidebar = constraints.maxWidth >= 900;
        return Scaffold(
          appBar: GlassAppBar(
            title: const Text('SHIFT AI'),
            leading: showSidebar
                ? null
                : Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.menu_rounded),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
            actions: [
              IconButton(
                tooltip: 'New chat',
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: () => context.read<ConversationStore>().startNewConversation(),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
          drawer: showSidebar ? null : const Drawer(child: ConversationSidebar()),
          body: Row(
            children: [
              if (showSidebar) const ConversationSidebar(),
              const Expanded(child: _ChatBody()),
            ],
          ),
        );
      },
    );
  }
}

class _ChatBody extends StatefulWidget {
  const _ChatBody();

  @override
  State<_ChatBody> createState() => _ChatBodyState();
}

class _ChatBodyState extends State<_ChatBody> {
  final _scrollController = ScrollController();

  void _scrollToBottom() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ConversationStore>();
    final messages = store.current?.messages ?? const [];

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: messages.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) => MessageBubble(message: messages[index]),
                ),
        ),
        const Divider(height: 1),
        const ChatInputBar(),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.auto_awesome_rounded, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: AppSpacing.md),
              Text('One studio. Every AI tool.', style: theme.textTheme.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Talk to SHIFT AI like you would a person — it routes your request to the right specialized studio automatically, or use a quick action below.',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.lg),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                alignment: WrapAlignment.center,
                children: [
                  for (final studio in const [
                    StudioType.imageStudio,
                    StudioType.videoStudio,
                    StudioType.voiceAvatarStudio,
                    StudioType.musicStudio,
                    StudioType.copyScriptsStudio,
                  ])
                    Chip(
                      avatar: Icon(studio.icon, size: 16, color: studio.accent),
                      label: Text(studio.shortName),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
