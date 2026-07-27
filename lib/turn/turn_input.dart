import '../data/models/attachment.dart';
import '../data/models/conversation.dart';
import '../data/models/studio_request.dart';
import '../services/chat_service.dart' show ChatOptions;

/// Everything one conversational turn is given.
///
/// Mirrors `ChatService.sendMessage`'s parameters so the pipeline can stand in
/// for it directly, but as a value object it can be built in a test with no
/// streaming, no controllers and no fakes.
class TurnInput {
  final Conversation conversation;
  final String userInput;

  /// Set when the turn came from a studio's structured form rather than free
  /// text, in which case the studio is already known and must not be
  /// re-classified.
  final StudioRequest? structuredRequest;

  final List<Attachment> attachments;
  final ChatOptions options;

  const TurnInput({
    required this.conversation,
    required this.userInput,
    this.structuredRequest,
    this.attachments = const [],
    this.options = ChatOptions.none,
  });
}
