import '../models/conversation.dart';
import '../models/studio_request.dart';
import '../models/studio_result.dart';
import '../models/studio_type.dart';

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

/// The specialized studio's generated result is ready to attach to the
/// message.
class StudioResultReady extends ChatEvent {
  final StudioResult result;
  const StudioResultReady(this.result);
}

class MessageComplete extends ChatEvent {
  const MessageComplete();
}

class MessageError extends ChatEvent {
  final String message;
  const MessageError(this.message);
}

/// Abstraction over "talk to the middleware AI, which talks to a specialized
/// model." [MockChatService] is the only implementation today; a real
/// backend can be swapped in later by implementing this interface and
/// changing one constructor call in `app.dart`.
abstract class ChatService {
  Stream<ChatEvent> sendMessage({
    required Conversation conversation,
    required String userInput,
    StudioRequest? structuredRequest,
  });
}
