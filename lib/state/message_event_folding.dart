import '../data/models/chat_message.dart';
import '../data/models/message_block.dart';
import '../services/chat_service.dart';

/// Stable block id for the deep-research progress chip (one per message).
const String deepResearchToolId = 'deep_research';

/// Folds one message-scoped [ChatEvent] into the assistant message being
/// streamed. Pure function so the event→block behavior is unit-testable
/// apart from the store. Conversation-scoped events (artifacts) are handled
/// by [ConversationStore] itself and pass through here untouched.
ChatMessage foldMessageEvent(ChatMessage message, ChatEvent event) {
  switch (event) {
    case RoutingDetected(:final studioType):
      return message.copyWith(studioType: studioType);

    case MessageDelta(:final chunk):
      final blocks = [...message.blocks];
      if (blocks.isNotEmpty && blocks.last is TextBlock) {
        final last = blocks.removeLast() as TextBlock;
        blocks.add(TextBlock(last.text + chunk));
      } else {
        blocks.add(TextBlock(chunk));
      }
      return message.copyWith(text: message.text + chunk, blocks: blocks);

    case ThinkingDelta(:final chunk):
      final blocks = [...message.blocks];
      if (blocks.isNotEmpty && blocks.last is ThinkingBlock) {
        final last = blocks.removeLast() as ThinkingBlock;
        blocks.add(ThinkingBlock(last.text + chunk));
      } else {
        blocks.add(ThinkingBlock(chunk));
      }
      return message.copyWith(blocks: blocks);

    case ToolUseStarted(:final id, :final tool, :final label):
      return message.copyWith(blocks: [
        ...message.blocks,
        ToolUseBlock(
          id: id,
          tool: tool,
          label: label,
          status: ToolUseStatus.running,
        ),
      ]);

    case ToolUseFinished(:final id, :final detail, :final failed):
      return message.copyWith(
        blocks: message.blocks
            .map((b) => b is ToolUseBlock && b.id == id
                ? b.copyWith(
                    status:
                        failed ? ToolUseStatus.failed : ToolUseStatus.done,
                    detail: detail,
                  )
                : b)
            .toList(),
      );

    case CitationsReady(:final citations):
      return message.copyWith(citations: citations);

    case ImageGenerated(:final pngBytes, :final alt):
      return message.copyWith(blocks: [
        ...message.blocks,
        ImageBlock(alt: alt, pngBytes: pngBytes),
      ]);

    case UsageReported(:final usage):
      return message.copyWith(usage: usage);

    case DeepResearchProgress(:final stage, :final round, :final query):
      final label = switch (stage) {
        'planning' => 'Planning research…',
        'searching' =>
          'Research round $round${query != null ? ': "$query"' : '…'}',
        'synthesizing' => 'Writing the report…',
        _ => 'Researching…',
      };
      final hasChip =
          message.blocks.any((b) => b is ToolUseBlock && b.id == deepResearchToolId);
      if (!hasChip) {
        return message.copyWith(blocks: [
          ...message.blocks,
          ToolUseBlock(
            id: deepResearchToolId,
            tool: 'deep_research',
            label: label,
            status: ToolUseStatus.running,
          ),
        ]);
      }
      return message.copyWith(
        blocks: message.blocks
            .map((b) => b is ToolUseBlock && b.id == deepResearchToolId
                ? b.copyWith(label: label)
                : b)
            .toList(),
      );

    case StudioResultReady(:final result):
      return message.copyWith(studioResult: result);

    case MessageComplete():
      // Anything still spinning settles when the turn ends.
      return message.copyWith(
        status: MessageStatus.complete,
        blocks: message.blocks
            .map((b) => b is ToolUseBlock && b.status == ToolUseStatus.running
                ? b.copyWith(status: ToolUseStatus.done)
                : b)
            .toList(),
      );

    case MessageIncomplete():
      // Cut off at the token ceiling: settle spinners but mark it continuable.
      return message.copyWith(
        status: MessageStatus.incomplete,
        blocks: message.blocks
            .map((b) => b is ToolUseBlock && b.status == ToolUseStatus.running
                ? b.copyWith(status: ToolUseStatus.done)
                : b)
            .toList(),
      );

    case MessageError(message: final errorText):
      return message.copyWith(
        text: message.text.isEmpty
            ? 'Something went wrong: $errorText'
            : message.text,
        blocks: message.blocks.isEmpty
            ? [TextBlock('Something went wrong: $errorText')]
            : message.blocks,
        status: MessageStatus.error,
      );

    // Conversation-scoped events — no message change here.
    case ArtifactCreated():
    case ArtifactUpdated():
      return message;
  }
}
