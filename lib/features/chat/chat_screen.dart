import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models/chat_message.dart';
import '../../data/models/conversation.dart';
import 'chat_find.dart';
import 'greeting.dart';
import 'conversation_export.dart';
import '../../data/stores/api_keys_store.dart';
import '../../core/state/artifact_panel_store.dart';
import '../../data/stores/conversation_store.dart';
import '../../data/stores/user_prefs_store.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/app_typography.dart';
import '../artifacts/artifact_panel.dart';
import 'composer/chat_input_bar.dart';
import 'message/message_view.dart';
import '../../core/widgets/glass_app_bar.dart';
import '../../core/shell/home_menu_button.dart';

/// The message column and composer share this width so the conversation
/// reads as a single centered prose column, like the Claude app.
const double _kProseColumnWidth = 760;

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 880;
        // A full-screen artifact covers the chat's own app bar. Left inside
        // the Scaffold body it sat *below* it, so the chat title stayed on
        // screen above the artifact title — two headers competing, and a row
        // of chat controls that do nothing for the artifact you are reading.
        return Stack(
          children: [
            _chatScaffold(context, constraints, sideBySide),
            Consumer<ArtifactPanelStore>(
              builder: (context, panel, _) =>
                  panel.isOpen && (!sideBySide || panel.expanded)
                      ? const Positioned.fill(child: ArtifactPanel())
                      : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  Widget _chatScaffold(
    BuildContext context,
    BoxConstraints constraints,
    bool sideBySide,
  ) {
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
              // covers the whole screen (handled by the caller's Stack). The
              // threshold is measured against the chat area (the sidebar is
              // already subtracted), so keep it low enough that a common
              // desktop window with the sidebar open still shows chat +
              // artifact together — the panel is at most 560px, leaving the
              // chat a comfortable column.
              final panelWidth = (constraints.maxWidth * 0.42).clamp(
                380.0,
                560.0,
              );
              return Row(
                children: [
                  const Expanded(child: _ChatBody()),
                  if (panel.isOpen && sideBySide && !panel.expanded)
                    SizedBox(
                      width: panelWidth,
                      child: const ArtifactPanel(),
                    ),
                ],
              );
            },
          ),
        );
  }
}

class _ChatTitle extends StatefulWidget {
  const _ChatTitle();

  @override
  State<_ChatTitle> createState() => _ChatTitleState();
}

class _ChatTitleState extends State<_ChatTitle> {
  bool _editing = false;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit(String title) {
    _controller.text = title;
    setState(() => _editing = true);
    _focus.requestFocus();
  }

  void _commit() {
    final convo = context.read<ConversationStore>().current;
    final text = _controller.text.trim();
    if (convo != null && text.isNotEmpty) {
      context.read<ConversationStore>().renameConversation(convo.id, text);
    }
    setState(() => _editing = false);
  }

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

    if (_editing && convo != null) {
      return SizedBox(
        width: 320,
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          style: theme.textTheme.titleMedium,
          decoration: const InputDecoration(isDense: true),
          onSubmitted: (_) => _commit(),
          onTapOutside: (_) => _commit(),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: GestureDetector(
            onDoubleTap: showTitle ? () => _startEdit(convo.title) : null,
            child: Text(
              showTitle ? convo.title : 'SHIFT AI',
              overflow: TextOverflow.ellipsis,
            ),
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
              case 'export_pdf':
                ConversationExport.exportPdf(convo);
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
            const PopupMenuItem(
              value: 'export_pdf',
              child: Text('Export as PDF'),
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

  // In-chat find (Cmd/Ctrl+F): match message indices + the active one.
  bool _findActive = false;
  final _findController = TextEditingController();
  final _findFocus = FocusNode();
  List<int> _matches = const [];
  int _activeMatch = 0;
  final Map<int, GlobalKey> _itemKeys = {};

  void _scrollToBottom() {
    if (_findActive || !_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _openFind() {
    setState(() => _findActive = true);
    _findFocus.requestFocus();
  }

  void _closeFind() {
    setState(() {
      _findActive = false;
      _findController.clear();
      _matches = const [];
      _activeMatch = 0;
    });
  }

  void _runFind(String query) {
    final messages = context.read<ConversationStore>().current?.messages ??
        const <ChatMessage>[];
    final matches = findMatchingMessageIndices(messages, query);
    setState(() {
      _matches = matches;
      _activeMatch = 0;
    });
    if (matches.isNotEmpty) _scrollToMatch();
  }

  void _stepMatch(int delta) {
    if (_matches.isEmpty) return;
    setState(() =>
        _activeMatch = (_activeMatch + delta) % _matches.length);
    if (_activeMatch < 0) _activeMatch += _matches.length;
    _scrollToMatch();
  }

  void _scrollToMatch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[_matches[_activeMatch]];
      final ctx = key?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.15, duration: const Duration(milliseconds: 250));
      }
    });
  }

  @override
  void dispose() {
    _findController.dispose();
    _findFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ConversationStore>();
    final messages = store.current?.messages ?? const [];
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    final activeMatchIndex =
        _matches.isEmpty ? -1 : _matches[_activeMatch];

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openFind,
        if (_findActive)
          const SingleActivator(LogicalKeyboardKey.escape): _closeFind,
      },
      child: Column(
        children: [
          if (_findActive)
            _FindBar(
              controller: _findController,
              focusNode: _findFocus,
              matchCount: _matches.length,
              activeMatch: _matches.isEmpty ? 0 : _activeMatch + 1,
              onChanged: _runFind,
              onNext: () => _stepMatch(1),
              onPrev: () => _stepMatch(-1),
              onClose: _closeFind,
            ),
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
                    itemBuilder: (context, index) {
                      final key = _itemKeys.putIfAbsent(index, GlobalKey.new);
                      final isActiveMatch = index == activeMatchIndex;
                      return Center(
                        key: key,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxWidth: _kProseColumnWidth,
                          ),
                          child: Container(
                            decoration: isActiveMatch
                                ? BoxDecoration(
                                    color: colors.surfaceAlt,
                                    borderRadius: BorderRadius.circular(
                                        AppSpacing.radiusMd),
                                    border: Border.all(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary),
                                  )
                                : null,
                            padding: isActiveMatch
                                ? const EdgeInsets.all(AppSpacing.sm)
                                : EdgeInsets.zero,
                            child: MessageView(
                              message: messages[index],
                              isLast: index == messages.length - 1,
                              onOpenArtifact: (ref) =>
                                  context.read<ArtifactPanelStore>().open(
                                        ref.artifactId,
                                        versionIndex: ref.versionIndex,
                                      ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _kProseColumnWidth),
              child: const ChatInputBar(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The in-chat find bar (Cmd/Ctrl+F): query field, match count, prev/next,
/// and close.
class _FindBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final int matchCount;
  final int activeMatch;
  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onClose;

  const _FindBar({
    required this.controller,
    required this.focusNode,
    required this.matchCount,
    required this.activeMatch,
    required this.onChanged,
    required this.onNext,
    required this.onPrev,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            const Icon(Icons.search_rounded, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                onSubmitted: (_) => onNext(),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Find in conversation…',
                ),
              ),
            ),
            Text(
              controller.text.isEmpty ? '' : '$activeMatch/$matchCount',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colors.textSecondary),
            ),
            IconButton(
              tooltip: 'Previous',
              iconSize: 18,
              onPressed: matchCount > 0 ? onPrev : null,
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            IconButton(
              tooltip: 'Next',
              iconSize: 18,
              onPressed: matchCount > 0 ? onNext : null,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
            IconButton(
              tooltip: 'Close',
              iconSize: 18,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

/// The new-chat screen: a greeting, then the composer.
///
/// Nothing else. The canned prompts that used to sit here wrote a message for
/// you and were identical on every visit; the studio chips that replaced them
/// were labels rather than actions, which made them a legend for a routing
/// layer the app deliberately keeps invisible. Routing happens on its own —
/// naming the ten destinations up front asks people to pick one.
class _EmptyState extends StatefulWidget {
  const _EmptyState();

  @override
  State<_EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<_EmptyState> {
  /// Fixed for as long as this blank chat is on screen. Rotating per frame
  /// would change the greeting while the user is reading it, and rotating per
  /// keystroke would be worse.
  late final int _seed = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final greeting = greetingFor(
      now: DateTime.now(),
      name: context.watch<UserPrefsStore>().nickname,
      seed: _seed,
    );

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
                size: 32,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                greeting,
                style: AppTypography.serifDisplay(
                  fontSize: 30,
                  color: theme.textTheme.headlineMedium!.color!,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
