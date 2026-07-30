
import 'package:flutter/material.dart';

import '../../../data/models/chat_message.dart';
import '../../../data/models/message_block.dart';
import '../../../data/models/studio_type.dart';
import '../../../core/theme/app_spacing.dart';
import 'markdown_message.dart';
import '../../studios/studio_result_card.dart';
import 'typing_indicator.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
import 'action_row.dart';
import 'artifact_card.dart';
import 'building_indicator.dart';
import 'citation_chips.dart';
import 'continue_button.dart';
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
    final streaming = message.status == MessageStatus.streaming;
    final nothingYet = message.blocks.every((b) => b is ThinkingBlock);
    final making = buildingLabel(message.studioType);

    final showTyping = streaming && nothingYet;

    // The long part of a build is *after* the prose. A code turn opens with a
    // sentence or two and then writes the file, which is withheld from the
    // transcript so the page does not arrive twice — so the screen went
    // completely still for the whole time the thing was actually being made.
    // The tool keeps working underneath the prose until the turn ends.
    final stillMaking = streaming && !nothingYet && making != null;

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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            // A turn that is *making* something waits differently from one
            // that is answering: it takes long enough that idle dots read as a
            // hang. The hammer keeps moving and the label says what is being
            // made.
            child: making == null
                ? const TypingIndicator()
                : BuildingIndicator(
                    label: making,
                    tool: buildingTool(message.studioType),
                  ),
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
        if (stillMaking)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: BuildingIndicator(
              label: making,
              tool: buildingTool(message.studioType),
            ),
          ),
        if (message.status == MessageStatus.incomplete)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: ContinueButton(messageId: message.id),
          ),
        // No suggested follow-ups. They were the same three lines under every
        // reply regardless of what the reply said — "explain that more simply"
        // beneath a generated image — so they read as filler rather than as
        // suggestions, and they pushed the composer down on a phone.
        ActionRow(message: message, visible: hovering),
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

/// What a studio is doing while you wait, or null when "thinking" is the
/// honest word for it.
///
/// Pure and top-level so the mapping is testable without pumping a widget:
/// which studios deserve the hammer is a product decision, not a paint detail.
String? buildingLabel(StudioType? studio) => switch (studio) {
      StudioType.codeStudio => 'Building',
      StudioType.imageStudio => 'Drawing',
      StudioType.videoStudio => 'Filming',
      StudioType.musicStudio => 'Scoring',
      StudioType.voiceStudio ||
      StudioType.voiceAvatarStudio ||
      StudioType.avatarStudio =>
        'Recording',
      StudioType.deckStudio => 'Building the deck',
      StudioType.brandPackStudio => 'Designing',
      StudioType.shortReelsStudio => 'Cutting',
      // Translation and plain answers are writing, not construction.
      StudioType.translateStudio ||
      StudioType.copyScriptsStudio ||
      StudioType.middleware ||
      null =>
        null,
    };

/// Which tool a studio's wait shows.
///
/// Drawing is not construction: a hammer over an image request is the wrong
/// verb, and the wrong verb in an animation is as noticeable as it is in a
/// sentence.
BuildingTool buildingTool(StudioType? studio) => switch (studio) {
      StudioType.imageStudio || StudioType.brandPackStudio =>
        BuildingTool.pencil,
      _ => BuildingTool.hammer,
    };
