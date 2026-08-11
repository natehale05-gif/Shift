import '../../data/api_keys_store.dart';
import '../../data/image_store.dart';
import '../chat/turn_controller.dart';

/// The turns Visual mode runs.
///
/// A distinct type so it can sit beside the chat's controller in one provider
/// tree, and a distinct *instance* for a reason that is not plumbing: a
/// picture made here would otherwise be appended to whatever conversation
/// happens to be open in Chat, invisibly, because Visual shows no transcript.
/// Someone would return to a chat about their tax return and find four
/// pictures of a cat in it.
///
/// So it is given no [ConversationStore] at all, which is what makes the turn
/// unrecorded: the picture *is* the record, and the gallery is where it lives.
/// It keeps the [ImageStore], so what it makes is kept exactly as a picture
/// made in Chat is.
///
/// Held at app level rather than created by the surface, so switching to Chat
/// and back does not abandon a generation already paid for.
class VisualTurns extends TurnController {
  VisualTurns({required ApiKeysStore keys, required ImageStore images})
      : super(keys: keys, images: images);
}
