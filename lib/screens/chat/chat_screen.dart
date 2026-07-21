import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/conversation.dart';
import '../../models/studio_type.dart';
import '../../services/conversation_export.dart';
import '../../state/api_keys_store.dart';
import '../../state/artifact_panel_store.dart';
import '../../state/conversation_store.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import '../../widgets/artifacts/artifact_panel.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/message_view.dart';
import '../../widgets/common/glass_app_bar.dart';
import '../../widgets/common/home_menu_button.dart';

/// The message column and composer share this width so the conversation
/// reads as a single centered prose column, like the Claude app.
const double _kProseColumnWidth = 760;

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Scaffold(
          appBar: GlassAppBar(
            title: const _ChatTitle(),
            leading: const HomeMenuButton(),
            actions: [
              const _ChatHeaderMenu(),
              IconButton(
                tooltip: 'New chat',
                icon: const Icon(Icons.add_comment_outlined),
                onPressed: () =>
                    context.read<ConversationStore>().startNewConversation(),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
          ),
          body: Consumer<ArtifactPanelStore>(
            builder: (context, panel, _) {
              // Side-by-side panel needs real width; below that the panel
              // covers the chat as a full overlay.
              final sideBySide = constraints.maxWidth >= 1100;
              final panelWidth = (constraints.maxWidth * 0.42).clamp(
                380.0,
                560.0,
              );
              return Stack(
                children: [
                  Row(
                    children: [
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
    final live = context.watch<ApiKeysStore>().isLive;
    final convo = context.watch<ConversationStore>().current;
    // Show the conversation's title once it has a name; the brand shows on the
    // empty/new state.
    final showTitle =
        convo != null && convo.messages.isNotEmpty && convo.title != 'New chat';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            showTitle ? convo.title : 'SHIFT AI',
            overflow: TextOverflow.ellipsis,
          ),
        ),
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
                color: live ? theme.colorScheme.primary : colors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Header Share button + overflow menu for the current conversation
/// (rename / star / pin / archive / export / delete). Hidden on an empty chat.
class _ChatHeaderMenu extends StatelessWidget {
  const _ChatHeaderMenu();

  Future<void> _rename(BuildContext context, Conversation convo) async {
    final store = context.read<ConversationStore>();
    final controller = TextEditingController(text: convo.title);
    final title = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: controller,
          autofocus: true,
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    if (title != null) store.renameConversation(convo.id, title);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ConversationStore>();
    final convo = store.current;
    if (convo == null || convo.messages.isEmpty) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Share — copies the transcript',
          icon: const Icon(Icons.ios_share_rounded),
          onPressed: () {
            Clipboard.setData(
              ClipboardData(text: ConversationExport.toMarkdown(convo)),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Conversation copied to clipboard as Markdown.'),
              ),
            );
          },
        ),
        PopupMenuButton<String>(
          tooltip: 'Chat options',
          icon: const Icon(Icons.more_horiz_rounded),
          onSelected: (action) {
            switch (action) {
              case 'rename':
                _rename(context, convo);
              case 'pin':
                store.togglePin(convo.id);
              case 'star':
                store.toggleStar(convo.id);
              case 'archive':
                store.toggleArchive(convo.id);
              case 'export_md':
                ConversationExport.downloadMarkdown(convo);
              case 'export_json':
                ConversationExport.downloadJson(convo);
              case 'delete':
                store.deleteConversation(convo.id);
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(
              value: 'pin',
              child: Text(convo.pinned ? 'Unpin' : 'Pin'),
            ),
            PopupMenuItem(
              value: 'star',
              child: Text(convo.starred ? 'Unstar' : 'Star'),
            ),
            PopupMenuItem(
              value: 'archive',
              child: Text(convo.archived ? 'Unarchive' : 'Archive'),
            ),
            const PopupMenuItem(
              value: 'export_md',
              child: Text('Export as Markdown'),
            ),
            const PopupMenuItem(
              value: 'export_json',
              child: Text('Export as JSON'),
            ),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
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
                'request to the right specialized studio automatically.',
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
                    StudioType.voiceStudio,
                    StudioType.avatarStudio,
                    StudioType.translateStudio,
                    StudioType.videoStudio,
                    StudioType.deckStudio,
                    StudioType.shortReelsStudio,
                    StudioType.musicStudio,
                    StudioType.brandPackStudio,
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
