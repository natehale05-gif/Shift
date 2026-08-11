import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app.dart';
import 'core/platform/boot_splash.dart';
import 'data/api_keys_store.dart';
import 'data/agent_run_store.dart';
import 'data/agent_store.dart';
import 'data/artifact_store.dart';
import 'data/conversation_store.dart';
import 'data/kv_store.dart';
import 'data/note_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Loaded before the first frame so the app never renders once as "no keys"
  // and then again with them — which on a slow disk reads as the keys having
  // been forgotten.
  // One KvStore, shared: two would each hold their own copy of the file and
  // the last write would silently discard the other's.
  final kv = KvStore();
  final keys = ApiKeysStore(kv);
  final conversations = ConversationStore(kv);
  final artifacts = ArtifactStore(kv);
  final agents = AgentStore(kv);
  final runs = AgentRunStore(kv);
  final notes = NoteStore(kv);
  await keys.load();
  await conversations.load();
  await artifacts.load();
  await agents.load();
  await notes.load();

  runApp(ShiftApp(
    keys: keys,
    conversations: conversations,
    artifacts: artifacts,
    agents: agents,
    runs: runs,
    notes: notes,
  ));

  // After the first real frame, not before: the HTML splash is what the user
  // is looking at until then, and taking it down early trades a branded screen
  // for a blank one.
  SchedulerBinding.instance.addPostFrameCallback((_) => dismissBootSplash());
}
