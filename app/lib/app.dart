import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/design/theme.dart';
import 'data/api_keys_store.dart';
import 'data/agent_run_store.dart';
import 'data/agent_store.dart';
import 'data/artifact_store.dart';
import 'data/conversation_store.dart';
import 'data/note_store.dart';
import 'features/chat/turn_controller.dart';
import 'features/code/agent_runner.dart';
import 'features/notes/note_cleaner.dart';
import 'shell/app_shell.dart';
import 'shell/shell_controller.dart';

class ShiftApp extends StatelessWidget {
  final ApiKeysStore keys;
  final ConversationStore conversations;
  final ArtifactStore artifacts;
  final AgentStore agents;
  final AgentRunStore runs;
  final NoteStore notes;

  const ShiftApp({
    super.key,
    required this.keys,
    required this.conversations,
    required this.artifacts,
    required this.agents,
    required this.runs,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ShellController()),
        ChangeNotifierProvider.value(value: keys),
        ChangeNotifierProvider.value(value: conversations),
        ChangeNotifierProvider.value(value: artifacts),
        ChangeNotifierProvider.value(value: agents),
        ChangeNotifierProvider.value(value: notes),
        ChangeNotifierProvider(create: (_) => NoteCleaner(keys: keys)),
        ChangeNotifierProvider(
          create: (_) => AgentRunner(agents: agents, runs: runs, keys: keys),
        ),
        ChangeNotifierProvider(
          create: (_) => TurnController(
            keys: keys,
            conversations: conversations,
            artifacts: artifacts,
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
