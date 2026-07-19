import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/chat_message.dart';
import '../../models/studio_type.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import 'markdown_message.dart';
import 'studio_result_card.dart';
import 'typing_indicator.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — no bubble, markdown-rendered — with a
/// hover action row underneath.
class MessageView extends StatefulWidget {
  final ChatMessage message;

  const MessageView({super.key, required this.message});

  @override
  State<MessageView> createState() => _MessageViewState();
}

class _MessageViewState extends State<MessageView> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return message.role == MessageRole.user
        ? _UserBubble(message: message)
        : MouseRegion(
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: _AssistantProse(message: message, hovering: _hovering),
          );
  }
}

class _UserBubble extends StatelessWidget {
  final ChatMessage message;

  const _UserBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          message.text,
          style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
        ),
      ),
    );
  }
}

class _AssistantProse extends StatelessWidget {
  final ChatMessage message;
  final bool hovering;

  const _AssistantProse({required this.message, required this.hovering});

  @override
  Widget build(BuildContext context) {
    final showTyping =
        message.status == MessageStatus.streaming && message.text.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.studioType != null &&
            message.studioType != StudioType.middleware)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _RoutingChip(studioType: message.studioType!),
          ),
        if (showTyping)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: TypingIndicator(),
          )
        else
          MarkdownMessage(text: message.text),
        if (message.studioResult != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: StudioResultCard(result: message.studioResult!),
          ),
        _ActionRow(message: message, visible: hovering),
      ],
    );
  }
}

/// "Routed -> Image Studio" chip above an assistant turn — the visible trace
/// of the middleware AI's routing decision.
class _RoutingChip extends StatelessWidget {
  final StudioType studioType;

  const _RoutingChip({required this.studioType});

  @override
  Widget build(BuildContext context) {
    final accent = studioType.accent;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(studioType.icon, size: 12, color: accent),
          const SizedBox(width: 4),
          Text(
            'Routed to ${studioType.shortName}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final ChatMessage message;
  final bool visible;

  const _ActionRow({required this.message, required this.visible});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    // Reserve the row's height even when hidden so hovering doesn't shift
    // the conversation layout.
    return AnimatedOpacity(
      opacity: visible && message.status == MessageStatus.complete ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      child: Row(
        children: [
          _ActionIcon(
            tooltip: 'Copy',
            icon: Icons.copy_rounded,
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: message.text)),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            TimeOfDay.fromDateTime(message.timestamp).format(context),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return IconButton(
      tooltip: tooltip,
      iconSize: 15,
      visualDensity: VisualDensity.compact,
      color: colors.textSecondary,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}
