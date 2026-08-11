import 'package:flutter/material.dart';

import '../../data/agent_store.dart';
import '../../data/api_keys_store.dart';
import '../../data/artifact_store.dart';
import '../../data/conversation_store.dart';
import '../../data/kv_store.dart';
import '../../data/note_store.dart';
import '../chat/turn_controller.dart';

/// Removes everything this app has stored on this device.
///
/// **Everything, not a curated subset.** The store is one key-value map, so
/// erasing it by name would mean listing every prefix any wave has ever
/// added — and the first one somebody forgets is the one that quietly
/// survives. Clearing the whole map is the only version of this that stays
/// true as the app grows.
///
/// The stores are reloaded afterwards, because each holds an in-memory copy:
/// without it the disk is empty and the app still shows the list it had.
Future<void> eraseEverything({
  required KvStore kv,
  required ConversationStore conversations,
  required ArtifactStore artifacts,
  required NoteStore notes,
  required AgentStore agents,
  required ApiKeysStore keys,
  required TurnController turn,
}) async {
  // Copied before iterating: removing from the map being walked is a
  // concurrent modification, and the half that survived would be arbitrary.
  for (final key in kv.keys().toList()) {
    await kv.remove(key);
  }

  turn.clear();
  await conversations.load();
  await artifacts.load();
  await notes.load();
  await agents.load();
  await keys.load();
}

/// Asks first, and says exactly what goes.
///
/// The list is the point. "All data" means nothing to someone deciding, and
/// the two items people would not think of — the pages, and the provider keys
/// they will have to paste again — are the ones worth naming.
Future<bool> confirmErase(BuildContext context) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete everything?'),
      content: const Text(
        'Every chat, page, note, agent and provider key stored on this device '
        'will be removed. Nothing is kept, and it cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete everything'),
        ),
      ],
    ),
  );
  return answer ?? false;
}
