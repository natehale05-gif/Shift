import '../../data/api_keys_store.dart';
import '../../data/artifact_store.dart';
import '../../data/conversation_store.dart';
import '../chat/turn_controller.dart';

/// The turns Design mode runs.
///
/// **Unlike Visual, this one keeps a conversation.** A picture is finished
/// when it arrives; a design is argued with — "make the heading bigger", "try
/// it darker" — and every one of those depends on what was said before. A
/// controller with no history would answer the second message as though the
/// first had not happened.
///
/// It has its own instance for the same reason Visual does: Design shows no
/// transcript, so sharing the chat's controller would file designs into
/// whatever conversation happened to be open, invisibly.
class DesignTurns extends TurnController {
  DesignTurns({
    required ApiKeysStore keys,
    required ConversationStore conversations,
    required ArtifactStore artifacts,
  }) : super(keys: keys, conversations: conversations, artifacts: artifacts);
}
