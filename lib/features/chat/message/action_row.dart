
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/models/chat_message.dart';
import '../../../services/speech/speech_service.dart';
import '../../../data/stores/app_settings_store.dart';
import '../../../data/stores/conversation_store.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
import 'action_icon.dart';
import 'regenerate_button.dart';
import 'variant_navigator.dart';

class ActionRow extends StatelessWidget {
  final ChatMessage message;
  final bool visible;

  const ActionRow({super.key, required this.message, required this.visible});

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
          if (message.hasVariants)
            VariantNavigator(message: message),
          ActionIcon(
            tooltip: 'Copy',
            icon: Icons.copy_rounded,
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: message.displayText)),
          ),
          RegenerateButton(message: message),
          ActionIcon(
            tooltip: 'Good response',
            icon: message.feedback == MessageFeedback.up
                ? Icons.thumb_up_rounded
                : Icons.thumb_up_outlined,
            color: message.feedback == MessageFeedback.up
                ? theme.colorScheme.primary
                : null,
            onPressed: () => context
                .read<ConversationStore>()
                .setFeedback(message.id, MessageFeedback.up),
          ),
          ActionIcon(
            tooltip: 'Bad response',
            icon: message.feedback == MessageFeedback.down
                ? Icons.thumb_down_rounded
                : Icons.thumb_down_outlined,
            color: message.feedback == MessageFeedback.down
                ? theme.colorScheme.primary
                : null,
            onPressed: () => context
                .read<ConversationStore>()
                .setFeedback(message.id, MessageFeedback.down),
          ),
          if (TtsService.isSupported)
            ActionIcon(
              tooltip: 'Read aloud',
              icon: Icons.volume_up_outlined,
              onPressed: () => TtsService.speak(message.displayText),
            ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            TimeOfDay.fromDateTime(message.timestamp).format(context),
            style: theme.textTheme.labelSmall
                ?.copyWith(color: colors.textSecondary),
          ),
          if (message.displayUsage != null &&
              context.watch<AppSettingsStore>().showUsage) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${message.displayUsage!.model} · '
              '${message.displayUsage!.inputTokens} in / '
              '${message.displayUsage!.outputTokens} out',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

/// Shown under a reply that hit the token ceiling — picks up where it left
/// off (Claude's "Continue").
