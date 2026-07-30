
import 'package:flutter/material.dart';

import '../../../data/models/chat_message.dart';
import '../../../data/models/message_block.dart';
import '../../../core/theme/app_spacing.dart';
import 'markdown_message.dart';
import '../../studios/studio_result_card.dart';
import 'typing_indicator.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
import 'action_row.dart';
import 'artifact_card.dart';
import 'citation_chips.dart';
import 'continue_button.dart';
import 'follow_up_chips.dart';
import 'image_block_view.dart';
import 'inline_artifact.dart';
import 'thinking_disclosure.dart';
import 'tool_chip.dart';

class AssistantProse extends StatelessWidget {
  final ChatMessage message;
  final bool hovering;
  final void Function(ArtifactRefBlock ref)? onOpenArtifact;
  final bool isLast;

  const AssistantProse({super.key, 
    required this.message,
    required this.hovering,
    this.onOpenArtifact,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    // One indicator for every kind of work. Thinking on its own is not
    // content — it is collapsed behind a disclosure, so a message holding
    // only thinking still looks like nothing is happening. Keeping the dots
    // up until real content arrives means a deck, a brand pack and a plain
    // answer all wait the same way, instead of each studio announcing itself
    // in its own prose.
    final showTyping = message.status == MessageStatus.streaming &&
        message.blocks.every((b) => b is ThinkingBlock);

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
            child: CitationChips(citations: citations),
          ),
        if (message.status == MessageStatus.incomplete)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: ContinueButton(messageId: message.id),
          ),
        ActionRow(message: message, visible: hovering),
        if (isLast && message.status == MessageStatus.complete)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.xs),
            child: FollowUpChips(),
          ),
      ],
    );
  }

  Widget _blockView(BuildContext context, MessageBlock block) {
    return switch (block) {
      TextBlock(:final text) => MarkdownMessage(text: text),
      ThinkingBlock(:final text) => ThinkingDisclosure(
          text: text,
          streaming: message.status == MessageStatus.streaming,
        ),
      ToolUseBlock() => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: ToolChip(block: block),
        ),
      ImageBlock() => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: ImageBlockView(block: block),
        ),
      ArtifactRefBlock() => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          // Interactive results render live inline (recipe/quiz/flashcards/
          // checklist); website/app builds stay a card that opens the panel.
          child: block.interactive
              ? InlineArtifact(block: block)
              : ArtifactCard(block: block, onOpen: onOpenArtifact),
        ),
    };
  }
}

/// Collapsed "Thought for a moment" disclosure hiding the model's
/// (simulated) reasoning, styled after the Claude app's thinking row.
