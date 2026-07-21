import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/artifact.dart';
import '../../models/attachment.dart';
import '../../models/chat_message.dart';
import '../../models/citation.dart';
import '../../models/message_block.dart';
import '../../services/chat_service.dart';
import '../../services/download_service.dart';
import '../../services/providers/provider_capability.dart';
import '../../services/speech/speech_service.dart';
import '../../state/api_keys_store.dart';
import '../../state/app_settings_store.dart';
import '../../state/conversation_store.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../artifacts/artifact_preview.dart';
import 'markdown_message.dart';
import 'studio_result_card.dart';
import 'typing_indicator.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
class MessageView extends StatefulWidget {
  final ChatMessage message;

  /// Invoked when the user taps an artifact card to open the artifacts panel;
  /// null renders the card non-interactive.
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

class _UserBubble extends StatefulWidget {
  final ChatMessage message;

  const _UserBubble({required this.message});

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  bool _hovering = false;

  ChatMessage get message => widget.message;

  Future<void> _edit() async {
    final store = context.read<ConversationStore>();
    final controller = TextEditingController(text: message.text);
    final newText = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit message'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save & resend'),
          ),
        ],
      ),
    );
    if (newText == null || newText.trim().isEmpty) return;
    // Everything after this message is replaced by the replayed turn.
    store.editAndResend(message.id, newText.trim());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Align(
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
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedOpacity(
                opacity: _hovering ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: IconButton(
                  tooltip: 'Edit & resend',
                  iconSize: 15,
                  visualDensity: VisualDensity.compact,
                  color: colors.textSecondary,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _edit,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
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
              ),
            ],
          ),
        ],
      ),
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

    // Render the response the ‹1/2› navigator currently points at (the newest
    // by default; older regenerations when the user steps back).
    final blocks = message.displayBlocks;
    final text = message.displayText;
    final studioResult = message.displayStudioResult;
    final citations = message.displayCitations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The routing is invisible on purpose — like Claude, you just get the
        // answer, not a "routed to X studio" chip.
        if (showTyping)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: TypingIndicator(),
          )
        else if (blocks.isEmpty && text.isNotEmpty)
          // Directly constructed / legacy messages carry text without
          // blocks — render the flat text through the same markdown path.
          MarkdownMessage(text: text)
        else ...[
          for (final block in blocks) _blockView(context, block),
        ],
        if (studioResult != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: StudioResultCard(result: studioResult),
          ),
        if (citations.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: _CitationChips(citations: citations),
          ),
        if (message.status == MessageStatus.incomplete)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: _ContinueButton(messageId: message.id),
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
          // Interactive results render live inline (recipe/quiz/flashcards/
          // checklist); website/app builds stay a card that opens the panel.
          child: block.interactive
              ? _InlineArtifact(block: block)
              : _ArtifactCard(block: block, onOpen: onOpenArtifact),
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

  Widget _image(Uint8List bytes) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Image.memory(bytes, fit: BoxFit.contain),
            ),
          ),
          TextButton.icon(
            onPressed: () => DownloadService.downloadBytes(
              bytes,
              '${DownloadService.slugify(block.alt, fallback: 'image')}.png',
              mimeType: 'image/png',
            ),
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Download'),
          ),
        ],
      );

  Widget _placeholder(BuildContext context, String label) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
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
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (block.pngBytes != null) return _image(block.pngBytes!);

    if (block.assetId != null) {
      // Reloaded session: bytes live in the IndexedDB asset store.
      return FutureBuilder<Uint8List?>(
        future:
            context.read<ConversationStore>().persistence.loadAsset(block.assetId!),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const SizedBox(
              height: 48,
              width: 48,
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
              ),
            );
          }
          final bytes = snapshot.data;
          return bytes != null
              ? _image(bytes)
              : _placeholder(
                  context, 'Image no longer stored — ${block.alt}');
        },
      );
    }

    return _placeholder(context, 'Image not saved — ${block.alt}');
  }
}

/// Renders an interactive artifact (recipe/quiz/flashcards/checklist) live
/// inline in the conversation — a real widget in the chat, not a link to
/// another page.
class _InlineArtifact extends StatelessWidget {
  final ArtifactRefBlock block;

  const _InlineArtifact({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final artifact =
        context.watch<ConversationStore>().current?.artifactById(block.artifactId);
    if (artifact == null) {
      // Artifact pruned or from another conversation — degrade to a card.
      return _ArtifactCard(block: block, onOpen: null);
    }
    final versionIndex =
        block.versionIndex.clamp(0, artifact.versions.length - 1);

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 680),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 540,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
            ),
            child: ArtifactPreview(
              artifact: artifact,
              versionIndex: versionIndex,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: TextButton.icon(
              onPressed: () => DownloadService.downloadText(
                artifact.versions[versionIndex].content,
                '${DownloadService.slugify(artifact.title)}.html',
              ),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text('Download'),
            ),
          ),
        ],
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
          if (message.hasVariants)
            _VariantNavigator(message: message),
          _ActionIcon(
            tooltip: 'Copy',
            icon: Icons.copy_rounded,
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: message.displayText)),
          ),
          _RegenerateButton(message: message),
          _ActionIcon(
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
          _ActionIcon(
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
            _ActionIcon(
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
class _ContinueButton extends StatelessWidget {
  final String messageId;

  const _ContinueButton({required this.messageId});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () =>
          context.read<ConversationStore>().continueReply(messageId),
      icon: const Icon(Icons.play_arrow_rounded, size: 16),
      label: const Text('Continue'),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Regenerate control: a plain tap re-runs with Auto; the menu also offers
/// "Retry with …" for each chat model the user has a key for.
class _RegenerateButton extends StatelessWidget {
  final ChatMessage message;

  const _RegenerateButton({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final keys = context.watch<ApiKeysStore>();
    final registry = keys.registry;
    final keyedProviders = [
      for (final d in registry.all)
        if (keys.hasKey(d.id) &&
            d.modelsFor(ProviderCapability.chat).isNotEmpty)
          d,
    ];

    void regen(String? pin) => context.read<ConversationStore>().regenerate(
          message.id,
          options: pin == null ? ChatOptions.none : ChatOptions(modelPin: pin),
        );

    return PopupMenuButton<String>(
      tooltip: 'Regenerate',
      position: PopupMenuPosition.under,
      onSelected: (value) => regen(value == 'auto' ? null : value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'auto', child: Text('Try again')),
        for (final provider in keyedProviders) ...[
          PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(
              provider.displayName.toUpperCase(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colors.textSecondary, letterSpacing: 0.5),
            ),
          ),
          for (final model in provider.modelsFor(ProviderCapability.chat))
            PopupMenuItem(
              value: model.id,
              child: Text('Retry with ${model.displayName}'),
            ),
        ],
      ],
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(Icons.refresh_rounded, size: 15, color: colors.textSecondary),
      ),
    );
  }
}

/// The ‹ 1/2 › switcher shown under a reply that has been regenerated, so the
/// user can step between the alternative responses.
class _VariantNavigator extends StatelessWidget {
  final ChatMessage message;

  const _VariantNavigator({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final store = context.read<ConversationStore>();
    final index = message.activeVariant;
    final count = message.variantCount;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionIcon(
          tooltip: 'Previous response',
          icon: Icons.chevron_left_rounded,
          onPressed:
              index > 0 ? () => store.selectVariant(message.id, index - 1) : null,
        ),
        Text(
          '${index + 1}/$count',
          style: theme.textTheme.labelSmall
              ?.copyWith(color: colors.textSecondary),
        ),
        _ActionIcon(
          tooltip: 'Next response',
          icon: Icons.chevron_right_rounded,
          onPressed: index < count - 1
              ? () => store.selectVariant(message.id, index + 1)
              : null,
        ),
      ],
    );
  }
}

class _ActionIcon extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return IconButton(
      tooltip: tooltip,
      iconSize: 15,
      visualDensity: VisualDensity.compact,
      color: color ?? colors.textSecondary,
      icon: Icon(icon),
      onPressed: onPressed,
    );
  }
}
