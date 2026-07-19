import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/studio_type.dart';
import '../../state/conversation_store.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import 'studio_request_sheets.dart';

/// Claude-style composer: a single rounded card holding the text field with
/// a row of controls beneath it — studios behind the "+" menu, a model chip,
/// and a circular terracotta send button.
class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  static const _studios = [
    StudioType.imageStudio,
    StudioType.videoStudio,
    StudioType.voiceAvatarStudio,
    StudioType.musicStudio,
    StudioType.copyScriptsStudio,
    StudioType.codeStudio,
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<ConversationStore>().sendMessage(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  Future<void> _openStudioSheet(StudioType studioType) async {
    final request = await showStudioRequestSheet(context, studioType);
    if (request == null || !mounted) return;
    context
        .read<ConversationStore>()
        .sendMessage('', structuredRequest: request);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.border),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 8,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Message SHIFT AI…',
                    filled: false,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md,
                    ),
                  ),
                ),
                Row(
                  children: [
                    _StudioMenuButton(onSelected: _openStudioSheet),
                    const SizedBox(width: AppSpacing.xs),
                    const _ModelChip(),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Voice input — coming soon',
                      icon: const Icon(Icons.mic_none_rounded, size: 20),
                      color: colors.textSecondary,
                      onPressed: null,
                      disabledColor: colors.textSecondary.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _SendButton(enabled: _hasText, onPressed: _send),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'SHIFT AI is in demo mode — responses are simulated.',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// The "+" menu: structured studio requests (attachments join this menu in a
/// later phase, matching the Claude composer's plus menu).
class _StudioMenuButton extends StatelessWidget {
  final ValueChanged<StudioType> onSelected;

  const _StudioMenuButton({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return PopupMenuButton<StudioType>(
      tooltip: 'Studios',
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      icon: Icon(Icons.add_rounded, color: colors.textSecondary),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final studio in _ChatInputBarState._studios)
          PopupMenuItem(
            value: studio,
            child: Row(
              children: [
                Icon(studio.icon, size: 18, color: studio.accent),
                const SizedBox(width: AppSpacing.md),
                Text(studio.shortName),
              ],
            ),
          ),
      ],
    );
  }
}

class _ModelChip extends StatelessWidget {
  const _ModelChip();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Tooltip(
      message: 'Model routing is automatic — the middleware AI picks the '
          'right studio for each request.',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Auto',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more_rounded,
              size: 14,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _SendButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.4,
      duration: const Duration(milliseconds: 120),
      child: SizedBox(
        width: 34,
        height: 34,
        child: IconButton.filled(
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
