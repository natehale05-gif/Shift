import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/design/theme.dart';
import 'data/api_keys_store.dart';
import 'data/agent_run_store.dart';
import 'data/agent_store.dart';
import 'data/artifact_store.dart';
import 'data/conversation_store.dart';
import 'data/image_store.dart';
import 'data/kv_store.dart';
import 'data/note_store.dart';
import 'features/chat/turn_controller.dart';
import 'features/code/agent_runner.dart';
import 'features/notes/note_cleaner.dart';
import 'features/design/design_turns.dart';
import 'features/visual/visual_turns.dart';
import 'features/work/work_runner.dart';
import 'shell/app_shell.dart';
import 'shell/shell_controller.dart';

class ShiftApp extends StatelessWidget {
  final ApiKeysStore keys;
  final ConversationStore conversations;
  final ArtifactStore artifacts;
  final AgentStore agents;
  final AgentRunStore runs;

  /// Work mode's folders and jobs, kept apart from Code's: a repository has no
  /// business appearing in a list of somebody's documents.
  final WorkAgents folders;
  final AgentRunStore jobRuns;
  final NoteStore notes;
  final ImageStore images;

  /// The store behind every other store. Provided so Settings can offer the
  /// one action that has to reach all of them at once.
  final KvStore kv;

  const ShiftApp({
    super.key,
    required this.keys,
    required this.conversations,
    required this.artifacts,
    required this.agents,
    required this.runs,
    required this.folders,
    required this.jobRuns,
    required this.notes,
    required this.images,
    required this.kv,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<KvStore>.value(value: kv),
        ChangeNotifierProvider(create: (_) => ShellController()),
        ChangeNotifierProvider.value(value: keys),
        ChangeNotifierProvider.value(value: conversations),
        ChangeNotifierProvider.value(value: artifacts),
        ChangeNotifierProvider.value(value: agents),
        ChangeNotifierProvider.value(value: folders),
        ChangeNotifierProvider.value(value: notes),
        ChangeNotifierProvider.value(value: images),
        ChangeNotifierProvider(create: (_) => NoteCleaner(keys: keys)),
        ChangeNotifierProvider(
          create: (_) => AgentRunner(agents: agents, runs: runs, keys: keys),
        ),
        ChangeNotifierProvider(
          create: (_) =>
              WorkRunner(agents: folders, runs: jobRuns, keys: keys),
        ),
        ChangeNotifierProvider(
          create: (_) => VisualTurns(keys: keys, images: images),
        ),
        ChangeNotifierProvider(
          create: (_) => DesignTurns(
            keys: keys,
            conversations: conversations,
            artifacts: artifacts,
          ),
        ),
        ChangeNotifierProvider(
          create: (_) => TurnController(
            keys: keys,
            conversations: conversations,
            artifacts: artifacts,
            notes: notes,
            images: images,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'SHIFT AI',
        debugShowCheckedModeBanner: false,
        theme: shiftTheme(Brightness.light, defaultTargetPlatform),
        darkTheme: shiftTheme(Brightness.dark, defaultTargetPlatform),

        // Follow the system until there is a setting to override it. Both
        // themes are built to the same standard, so neither is a fallback.
        themeMode: ThemeMode.system,

        home: const AppShell(),
      ),
    );
  }
}
