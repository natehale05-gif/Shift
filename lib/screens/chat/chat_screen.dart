import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/studio_type.dart';
import '../../state/api_keys_store.dart';
import '../../state/artifact_panel_store.dart';
import '../../state/conversation_store.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../widgets/artifacts/artifact_panel.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/conversation_sidebar.dart';
import '../../widgets/chat/message_view.dart';
import '../../widgets/common/glass_app_bar.dart';

/// The message column and composer share this width so the conversation
/// reads as a single centered prose column, like the Claude app.
const double _kProseColumnWidth = 760;

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  bool _sidebarOpen = true;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wideLayout = constraints.maxWidth >= 900;
        return Scaffold(
          appBar: GlassAppBar(
            title: const _ChatTitle(),
            leading: Builder(
              builder: (context) => IconButton(
                tooltip: wideLayout ? 'Toggle sidebar' : 'Chats',
                icon: Icon(
                  wideLayout
                      ? Icons.view_sidebar_outlined
                      : Icons.menu_rounded,
                ),
                onPressed: () {
                  if (wideLayout) {
                    setState(() => _sidebarOpen = !_sidebarOpen);
                  } else {
                    Scaffold.of(context).openDrawer();
                  }
                },
              ),
            ),
            actions: [
              IconButton(
                tooltip: 'New chat',
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: () =>
                    context.read<ConversationStore>().startNewConversation(),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
          drawer:
              wideLayout ? null : const Drawer(child: ConversationSidebar()),
          body: Consumer<ArtifactPanelStore>(
            builder: (context, panel, _) {
              // Side-by-side panel needs real width; below that the panel
              // covers the chat as a full overlay.
              final sideBySide = constraints.maxWidth >= 1100;
              final panelWidth =
                  (constraints.maxWidth * 0.42).clamp(380.0, 560.0);
              return Stack(
                children: [
                  Row(
                    children: [
                      if (wideLayout)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: _sidebarOpen ? 280 : 0,
                          child: const ClipRect(
                            child: OverflowBox(
                              alignment: Alignment.centerLeft,
                              minWidth: 280,
                              maxWidth: 280,
                              child: ConversationSidebar(),
                            ),
                          ),
                        ),
                      const Expanded(child: _ChatBody()),
                      if (panel.isOpen && sideBySide)
                        SizedBox(
                          width: panelWidth,
                          child: const ArtifactPanel(),
                        ),
                    ],
                  ),
                  if (panel.isOpen && !sideBySide)
                    const Positioned.fill(child: ArtifactPanel()),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _ChatTitle extends StatelessWidget {
  const _ChatTitle();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final live = context.watch<ApiKeysStore>().hasAnthropicKey;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('SHIFT AI'),
        const SizedBox(width: AppSpacing.sm),
        Tooltip(
          message: live
              ? 'Live — chat calls the real API with your key.'
              : 'Simulated — add an API key in Settings for live AI.',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: live
                  ? theme.colorScheme.primary.withValues(alpha: 0.12)
                  : colors.surfaceAlt,
              borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
              border: Border.all(
                color: live ? theme.colorScheme.primary : colors.border,
              ),
            ),
            child: Text(
              live ? 'Live' : 'Simulated',
              style: theme.textTheme.labelSmall?.copyWith(
                color: live
                    ? theme.colorScheme.primary
                    : colors.textSecondary,
              ),
            ),
          ),
        ),
      ],
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xl,
                  ),
                  itemCount: messages.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.lg),
                  itemBuilder: (context, index) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: _kProseColumnWidth,
                      ),
                      child: MessageView(
                        message: messages[index],
                        onOpenArtifact: (ref) =>
                            context.read<ArtifactPanelStore>().open(
                                  ref.artifactId,
                                  versionIndex: ref.versionIndex,
                                ),
                      ),
                    ),
                  ),
                ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _kProseColumnWidth),
            child: const ChatInputBar(),
          ),
        ),
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
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 36,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'One studio. Every AI tool.',
                style: AppTypography.serifDisplay(
                  fontSize: 32,
                  color: theme.textTheme.headlineMedium!.color!,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Talk to SHIFT AI like you would a person — it routes your '
                'request to the right specialized studio automatically, or '
                'pick a studio from the + menu below.',
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
                    StudioType.codeStudio,
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
