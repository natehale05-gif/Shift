import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/studio_type.dart';

/// If the previous assistant turn asked a clarifying question about a
/// studio request, returns the studio and the original request text — so a
/// terse follow-up ("navy blue") can be merged into a complete one ("make
/// me a logo navy blue") instead of the turn being reclassified from
/// scratch. Every clarifying question this app asks ends with '?'; a
/// resolved turn's own text never does — a simple, reliable signal that
/// needs no extra persisted state.
///
/// By the time a [ChatService] sees a [Conversation], the store has already
/// appended this turn's own user message and an empty streaming-placeholder
/// assistant message as the last two entries, so the *previous* turn sits
/// three and four messages from the end.
(StudioType, String)? findPendingClarification(Conversation conversation) {
  final messages = conversation.messages;
  if (messages.length < 4) return null;
  final priorAssistant = messages[messages.length - 3];
  final priorUser = messages[messages.length - 4];
  if (priorAssistant.role != MessageRole.assistant) return null;
  if (priorUser.role != MessageRole.user) return null;
  final studio = priorAssistant.studioType;
  if (studio == null || studio == StudioType.middleware) return null;
  if (!priorAssistant.text.trimRight().endsWith('?')) return null;
  return (studio, priorUser.text);
}
