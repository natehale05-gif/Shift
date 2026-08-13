import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'app.dart';
import 'core/platform/boot_splash.dart';
import 'core/update/update_installer.dart';
import 'data/api_keys_store.dart';
import 'data/agent_run_store.dart';
import 'data/agent_store.dart';
import 'data/artifact_store.dart';
import 'data/asset_store.dart';
import 'data/conversation_store.dart';
import 'data/image_store.dart';
import 'data/kv_store.dart';
import 'data/note_store.dart';
import 'data/update_store.dart';
import 'features/work/work_runner.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // An update downloaded during the last session is swapped in here, before
  // any UI exists. Two reasons, and the first is not negotiable: a running
  // process cannot replace the directory it is executing from. The second is
  // the design choice — the app never quits out from under somebody
  // mid-sentence to update itself; it stages quietly and applies at the next
  // launch. Never returns if it fires, because this process is replaced.
  if (hasStagedUpdate) {
    if (await applyStagedUpdate()) return;
  }

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
  final folders = WorkAgents(kv);
  final jobRuns = AgentRunStore(kv, namespace: 'work');
  final notes = NoteStore(kv);
  final images = ImageStore(kv, AssetStore());
  await keys.load();
  await conversations.load();
  await artifacts.load();
  await agents.load();
  await folders.load();
  await notes.load();
  await images.load();

  // Bytes no index entry points at, left by a save interrupted between the
  // two writes. Nothing can ever show or delete them, so they only accumulate
  // — and in a browser they spend a quota the user cannot see. Unawaited: it
  // touches only orphans, so nothing on screen waits for it.
  images.sweep().ignore();

  // Loaded before `runApp` so the card never renders once as "no version" and
  // then again with one. The *check* is deliberately not awaited here.
  final updates = UpdateStore(kv);
  await updates.load();

  runApp(ShiftApp(
    keys: keys,
    conversations: conversations,
    artifacts: artifacts,
    agents: agents,
    runs: runs,
    folders: folders,
    jobRuns: jobRuns,
    notes: notes,
    images: images,
    kv: kv,
    updates: updates,
  ));

  // After the first real frame, not before: the HTML splash is what the user
  // is looking at until then, and taking it down early trades a branded screen
  // for a blank one.
  SchedulerBinding.instance.addPostFrameCallback((_) {
    dismissBootSplash();

    // Off the boot path for the same reason: this makes a network request, and
    // a launch that waits on GitHub is a launch that is slow whenever GitHub
    // is. `checkIfDue` is throttled to once a day and every failure inside it
    // is swallowed, so nothing here can surface an error or block a frame.
    updates.checkIfDue().ignore();
  });
}
