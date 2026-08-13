import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/design/theme.dart';
import 'backend/backend_config.dart';
import 'backend/no_backend.dart';
import 'backend/shift_backend.dart';
import 'backend/supabase_backend.dart';
import 'data/account_store.dart';
import 'data/api_keys_store.dart';
import 'data/agent_run_store.dart';
import 'data/agent_store.dart';
import 'data/artifact_store.dart';
import 'data/conversation_store.dart';
import 'data/image_store.dart';
import 'data/kv_store.dart';
import 'data/update_store.dart';
import 'data/note_store.dart';
import 'features/chat/turn_controller.dart';
import 'features/code/agent_runner.dart';
import 'features/notes/note_cleaner.dart';
import 'features/design/design_turns.dart';
import 'features/visual/visual_turns.dart';
import 'features/work/work_runner.dart';
import 'shell/app_shell.dart';
import 'shell/shell_controller.dart';
import 'shell/sign_in_gate.dart';

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
  final UpdateStore updates;

  /// Which host is behind the app, chosen here and nowhere else.
  ///
  /// The composition root is the one place `tool/scan_backend_boundary.py`
  /// allows to name an implementation — everything above talks to
  /// [ShiftBackend].
  ///
  /// [NoBackend] is what a build with no configured host gets, and such a build
  /// is **not** put behind [SignInGate] — there would be nothing to sign in to,
  /// so the gate would be an app that never opens. Shipped builds all carry a
  /// host, so in practice this arm is a local build without the defines.
  static ShiftBackend backendFor(KvStore kv) {
    final config = BackendConfig.fromEnvironment();
    if (config == null) return NoBackend();

    return SupabaseBackend(
      config: config,
      // The session is a short string like everything else this store holds,
      // and it has to survive a reload — otherwise signing in would be a
      // per-tab act, and on a phone that is every time the browser is
      // reclaimed.
      onSessionChanged: (session) async {
        if (session == null) {
          await kv.remove(_sessionKey);
        } else {
          await kv.put(_sessionKey, jsonEncode(session.toJson()));
        }
      },
      loadStoredSession: () async {
        final stored = kv.get(_sessionKey);
        if (stored == null) return null;
        try {
          return ShiftSession.fromJson(
              jsonDecode(stored) as Map<String, dynamic>);
        } catch (_) {
          // A session written by an older build, or a truncated write. Treated
          // as signed out rather than as a crash: the remedy is signing in,
          // which is one tap, and the alternative is an app that will not open.
          return null;
        }
      },
    );
  }

  static const _sessionKey = 'account.session';

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
    required this.updates,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<KvStore>.value(value: kv),
        ChangeNotifierProvider(create: (_) => ShellController()),

        // Built in `main` so its version is read before the first frame, and
        // its check fires after it — a launch that waits on GitHub is a launch
        // that is slow whenever GitHub is.
        ChangeNotifierProvider.value(value: updates),
        ChangeNotifierProvider(
          create: (_) => AccountStore(backend: backendFor(kv))..start(Uri.base),
        ),
        ChangeNotifierProvider.value(value: keys),
        ChangeNotifierProvider.value(value: conversations),
        ChangeNotifierProvider.value(value: artifacts),
        ChangeNotifierProvider.value(value: agents),
        ChangeNotifierProvider.value(value: folders),
        ChangeNotifierProvider.value(value: notes),
        ChangeNotifierProvider.value(value: images),
        // Everything below takes the account, and that is the whole of what
        // makes a membership buy anything: without it these resolve
        // credentials from this device's keys alone, so a member with SHIFT's
        // keys on the server is told no provider is set up. `context` rather
        // than `_` because MultiProvider nests — `AccountStore` above is
        // already in scope for each of these.
        ChangeNotifierProvider(
          create: (context) => NoteCleaner(
            keys: keys,
            account: context.read<AccountStore>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => AgentRunner(
            agents: agents,
            runs: runs,
            keys: keys,
            account: context.read<AccountStore>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => WorkRunner(
            agents: folders,
            runs: jobRuns,
            keys: keys,
            account: context.read<AccountStore>(),
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => VisualTurns(
            keys: keys,
            account: context.read<AccountStore>(),
            images: images,
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => DesignTurns(
            keys: keys,
            account: context.read<AccountStore>(),
            conversations: conversations,
            artifacts: artifacts,
          ),
        ),
        ChangeNotifierProvider(
          create: (context) => TurnController(
            keys: keys,
            account: context.read<AccountStore>(),
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

        // The app is behind an account. The gate is here rather than inside
        // the shell so nothing below it has to ask whether it is allowed to
        // exist — every mode, store and surface runs only for a signed-in
        // person, or not at all.
        home: const SignInGate(child: AppShell()),
      ),
    );
  }
}
