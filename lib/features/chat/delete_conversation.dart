import 'package:flutter/material.dart';

import '../../data/artifact_store.dart';
import '../../data/conversation_store.dart';
import 'turn_controller.dart';

/// Deleting a conversation, in one place.
///
/// Three things have to happen together and it is the kind of set where
/// forgetting one is invisible: the transcript goes, **the pages it made go**,
/// and if it is the conversation on screen the screen has to let go of it —
/// otherwise the app keeps showing something that no longer exists and writes
/// it back on the next keystroke.
Future<void> deleteConversation(
  String id, {
  required ConversationStore conversations,
  required ArtifactStore artifacts,
  required TurnController turn,
}) async {
  // The open one first: dropping it before the stores change means nothing
  // rebuilds against a half-deleted conversation.
  if (turn.conversationId == id) turn.clear();

  await conversations.remove(id);
  await artifacts.removeConversation(id);
}

/// Asks first.
///
/// A deletion with no undo gets a confirmation — the app has no trash and no
/// history, so a mis-tap in a list is the whole conversation.
Future<bool> confirmDelete(BuildContext context, String title) => confirmLoss(
      context,
      question: 'Delete this chat?',
      // Names what goes, because the pages are the part people would not
      // expect to lose and would miss most.
      detail: '"$title" and anything it made will be removed from this '
          'device. This cannot be undone.',
      action: 'Delete',
    );

/// The one dialog for "this is about to be gone".
///
/// Wording is a parameter rather than a second dialog beside this one: two
/// confirmations built separately drift in shape — button order, capitalised
/// verbs, which side Cancel sits on — and the drift is only ever noticed by
/// somebody who has just lost something.
Future<bool> confirmLoss(
  BuildContext context, {
  required String question,
  required String detail,
  required String action,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(question),
      content: Text(detail),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return answer ?? false;
}
