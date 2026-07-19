import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/artifact.dart';
import '../../models/attachment.dart';
import '../../models/chat_message.dart';
import '../../models/citation.dart';
import '../../models/message_block.dart';
import '../../models/studio_type.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import 'markdown_message.dart';
import 'studio_result_card.dart';
import 'typing_indicator.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
class MessageView extends StatefulWidget {
  final ChatMessage message;

  /// Invoked when the user taps an artifact card (opens the panel once the
  /// artifacts panel ships; null renders the card non-interactive).
  final void Function(ArtifactRefBlock ref)? onOpenArtifact;

  const MessageView({super.key, required this.message, this.onOpenArtifact});

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
            child: _AssistantProse(
              message: message,
              hovering: _hovering,
              onOpenArtifact: widget.onOpenArtifact,
            ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (message.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final attachment in message.attachments)
                    Chip(
                      avatar: Icon(
                        switch (attachment.kind) {
                          AttachmentKind.image => Icons.image_outlined,
                          AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
                          AttachmentKind.text => Icons.description_outlined,
                        },
                        size: 15,
                        color: colors.textSecondary,
                      ),
                      label: Text(
                        attachment.name,
                        style: theme.textTheme.labelSmall,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ),
          Container(
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
        ],
      ),
    );
  }
}

class _AssistantProse extends StatelessWidget {
  final ChatMessage message;
  final bool hovering;
  final void Function(ArtifactRefBlock ref)? onOpenArtifact;

  const _AssistantProse({
    required this.message,
    required this.hovering,
    this.onOpenArtifact,
  });

  @override
  Widget build(BuildContext context) {
    final showTyping =
        message.status == MessageStatus.streaming && message.blocks.isEmpty;

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
        else if (message.blocks.isEmpty && message.text.isNotEmpty)
          // Directly constructed / legacy messages carry text without
          // blocks — render the flat text through the same markdown path.
          MarkdownMessage(text: message.text)
        else ...[
          for (final block in message.blocks) _blockView(context, block),
        ],
        if (message.studioResult != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: StudioResultCard(result: message.studioResult!),
          ),
        if (message.citations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: _CitationChips(citations: message.citations),
          ),
        _ActionRow(message: message, visible: hovering),
      ],
    );
  }

  Widget _blockView(BuildContext context, MessageBlock block) {
    return switch (block) {
      TextBlock(:final text) => MarkdownMessage(text: text),
      ThinkingBlock(:final text) => _ThinkingDisclosure(
          text: text,
          streaming: message.status == MessageStatus.streaming,
        ),
      ToolUseBlock() => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: _ToolChip(block: block),
        ),
      ImageBlock() => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: _ImageBlockView(block: block),
        ),
      ArtifactRefBlock() => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: _ArtifactCard(block: block, onOpen: onOpenArtifact),
        ),
    };
  }
}

/// Collapsed "Thought for a moment" disclosure hiding the model's
/// (simulated) reasoning, styled after the Claude app's thinking row.
class _ThinkingDisclosure extends StatefulWidget {
  final String text;
  final bool streaming;

  const _ThinkingDisclosure({required this.text, required this.streaming});

  @override
  State<_ThinkingDisclosure> createState() => _ThinkingDisclosureState();
}

class _ThinkingDisclosureState extends State<_ThinkingDisclosure> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.psychology_alt_outlined,
                  size: 15,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.streaming ? 'Thinking…' : 'Thought for a moment',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: colors.textSecondary),
                ),
                Icon(
                  _expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 16,
                  color: colors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: colors.border, width: 2),
              ),
            ),
            child: Text(
              widget.text,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: colors.textSecondary, height: 1.5),
            ),
          ),
      ],
    );
  }
}

class _ToolChip extends StatelessWidget {
  final ToolUseBlock block;

  const _ToolChip({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final running = block.status == ToolUseStatus.running;
    final failed = block.status == ToolUseStatus.failed;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (running)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: theme.colorScheme.primary,
              ),
            )
          else
            Icon(
              failed ? Icons.error_outline_rounded : Icons.check_rounded,
              size: 14,
              color: failed
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              block.detail != null && !running
                  ? '${block.label}  ·  ${block.detail}'
                  : block.label,
              style: theme.textTheme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ImageBlockView extends StatelessWidget {
  final ImageBlock block;

  const _ImageBlockView({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    if (block.pngBytes == null) {
      // Bytes aren't persisted yet (localStorage quota) — after a reload
      // only this placeholder remains.
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 16, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Image not saved — ${block.alt}',
              style: theme.textTheme.labelMedium,
            ),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Image.memory(block.pngBytes!, fit: BoxFit.contain),
      ),
    );
  }
}

/// Tappable card representing an artifact created/updated by this turn.
class _ArtifactCard extends StatelessWidget {
  final ArtifactRefBlock block;
  final void Function(ArtifactRefBlock ref)? onOpen;

  const _ArtifactCard({required this.block, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return InkWell(
      borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      onTap: onOpen != null ? () => onOpen!(block) : null,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(
                switch (block.kind) {
                  ArtifactKind.html => Icons.language_rounded,
                  ArtifactKind.svg => Icons.polyline_rounded,
                  ArtifactKind.markdown => Icons.article_outlined,
                  ArtifactKind.code => Icons.code_rounded,
                },
                size: 18,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.title,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Artifact · v${block.versionIndex + 1}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _CitationChips extends StatelessWidget {
  final List<Citation> citations;

  const _CitationChips({required this.citations});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (var i = 0; i < citations.length; i++)
          Tooltip(
            message: citations[i].url,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                border: Border.all(color: colors.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${i + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 5),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(
                      citations[i].title,
                      style: theme.textTheme.labelSmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
          if (message.usage != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${message.usage!.model} · ${message.usage!.inputTokens} in / '
              '${message.usage!.outputTokens} out',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colors.textSecondary),
            ),
          ],
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
