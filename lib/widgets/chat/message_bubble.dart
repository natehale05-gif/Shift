import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../models/studio_type.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import 'studio_result_card.dart';
import 'typing_indicator.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    final bubbleColor = isUser ? theme.colorScheme.primary : theme.colorScheme.surface;
    final textColor = isUser ? theme.colorScheme.onPrimary : theme.textTheme.bodyLarge?.color;

    final showTyping = !isUser &&
        message.status == MessageStatus.streaming &&
        message.text.isEmpty;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isUser && message.studioType != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4, left: 4),
                child: _StudioBadge(studioType: message.studioType!),
              ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(AppSpacing.radiusLg),
                  topRight: const Radius.circular(AppSpacing.radiusLg),
                  bottomLeft: Radius.circular(isUser ? AppSpacing.radiusLg : 4),
                  bottomRight: Radius.circular(isUser ? 4 : AppSpacing.radiusLg),
                ),
                border: isUser ? null : Border.all(color: colors.border),
              ),
              child: showTyping
                  ? const TypingIndicator()
                  : Text(
                      message.text,
                      style: theme.textTheme.bodyLarge?.copyWith(color: textColor),
                    ),
            ),
            if (message.studioResult != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: StudioResultCard(result: message.studioResult!),
              ),
          ],
        ),
      ),
    );
  }
}

class _StudioBadge extends StatelessWidget {
  final StudioType studioType;
  const _StudioBadge({required this.studioType});

  @override
  Widget build(BuildContext context) {
    final accent = studioType.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(studioType.icon, size: 12, color: accent),
          const SizedBox(width: 4),
          Text(
            studioType.shortName,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: accent),
          ),
        ],
      ),
    );
  }
}
