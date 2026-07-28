import 'dart:typed_data';

import '../data/models/artifact.dart';
import '../data/models/attachment.dart';
import '../data/models/citation.dart';
import '../data/models/conversation.dart';
import '../data/models/studio_request.dart';
import '../data/models/studio_result.dart';
import '../data/models/studio_type.dart';
import '../data/models/usage_report.dart';

sealed class ChatEvent {
  const ChatEvent();
}

/// The middleware AI has decided which specialized studio will handle this
/// request (or that it's answering directly, for [StudioType.middleware]).
class RoutingDetected extends ChatEvent {
  final StudioType studioType;
  const RoutingDetected(this.studioType);
}

/// One streamed chunk of the assistant's reply text.
class MessageDelta extends ChatEvent {
  final String chunk;
  const MessageDelta(this.chunk);
}

/// One streamed chunk of the model's (summarized) reasoning.
class ThinkingDelta extends ChatEvent {
  final String chunk;
  const ThinkingDelta(this.chunk);
}

/// A tool invocation began (web search, code execution, deep research…).
/// Paired with a later [ToolUseFinished] carrying the same [id].
class ToolUseStarted extends ChatEvent {
  final String id;
  final String tool;
  final String label;
  const ToolUseStarted({
    required this.id,
    required this.tool,
    required this.label,
  });
}

class ToolUseFinished extends ChatEvent {
  final String id;
  final String? detail;
  final bool failed;
  const ToolUseFinished({required this.id, this.detail, this.failed = false});
}

/// Web sources backing this reply, to render as citation chips.
class CitationsReady extends ChatEvent {
  final List<Citation> citations;
  const CitationsReady(this.citations);
}

/// A generated image (PNG bytes) to render inline in the reply.
class ImageGenerated extends ChatEvent {
  final Uint8List pngBytes;
  final String alt;
  const ImageGenerated({required this.pngBytes, required this.alt});
}

/// A new artifact was created by this turn.
class ArtifactCreated extends ChatEvent {
  final Artifact artifact;
  const ArtifactCreated(this.artifact);
}

/// An existing artifact gained a new version.
class ArtifactUpdated extends ChatEvent {
  final Artifact artifact;
  const ArtifactUpdated(this.artifact);
}

class UsageReported extends ChatEvent {
  final UsageReport usage;
  const UsageReported(this.usage);
}

/// Progress through a deep-research run. [stage] is one of
/// 'planning' | 'searching' | 'synthesizing'.
class DeepResearchProgress extends ChatEvent {
  final String stage;
  final int round;
  final String? query;
  final int? sourceCount;
  const DeepResearchProgress({
    required this.stage,
    this.round = 0,
    this.query,
    this.sourceCount,
  });
}

/// The specialized studio's generated result is ready to attach to the
/// message.
class StudioResultReady extends ChatEvent {
  final StudioResult result;
  const StudioResultReady(this.result);
}

class MessageComplete extends ChatEvent {
  const MessageComplete();
}

/// The reply ended because it hit the output-token ceiling, not because the
/// model was done — the UI offers a "Continue" action to pick up where it
/// stopped.
class MessageIncomplete extends ChatEvent {
  const MessageIncomplete();
}

class MessageError extends ChatEvent {
  final String message;
  const MessageError(this.message);
}

/// Per-message send options set from the composer (model pin, tool
/// toggles). All defaults mean "let the middleware decide."
class ChatOptions {
  /// Exact model id to use, bypassing the router. Null = auto-route.
  final String? modelPin;
  final bool webSearch;
  final bool codeExecution;
  final bool deepResearch;

  /// Whether the model may spend extended thinking on this turn. Defaults to
  /// on (matches the always-adaptive behavior); the composer toggle can turn
  /// it off for a faster, non-reasoning reply.
  final bool extendedThinking;

  /// Assembled system prompt for this turn (persona + user prefs + project
  /// context), built by `assembleSystemPrompt`.
  final String? systemPrompt;

  const ChatOptions({
    this.modelPin,
    this.webSearch = false,
    this.codeExecution = false,
    this.deepResearch = false,
    this.extendedThinking = true,
    this.systemPrompt,
  });

  static const none = ChatOptions();
}

/// Abstraction over "talk to the middleware AI, which talks to a specialized
/// model." [MockChatService] simulates everything locally; a real
/// implementation calls provider APIs with the user's own keys. The UI never
/// branches on which one is active — both speak the same [ChatEvent] stream.
abstract class ChatService {
  Stream<ChatEvent> sendMessage({
    required Conversation conversation,
    required String userInput,
    StudioRequest? structuredRequest,
    List<Attachment> attachments = const [],
    ChatOptions options = ChatOptions.none,
  });
}
