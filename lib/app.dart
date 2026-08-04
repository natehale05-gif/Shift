import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'backend/backend_config.dart';
import 'backend/no_backend.dart';
import 'backend/shift_backend.dart';
import 'backend/supabase_backend.dart';
import 'core/shell/home_shell.dart';
import 'features/memory/memory_service.dart';
import 'turn/backends/mock_backend.dart';
import 'data/persistence/persistence_service.dart';
import 'turn/backends/live_backend.dart';
import 'data/stores/account_store.dart';
import 'data/stores/api_keys_store.dart';
import 'data/stores/app_settings_store.dart';
import 'core/state/artifact_panel_store.dart';
import 'data/stores/conversation_store.dart';
import 'data/stores/memory_store.dart';
import 'data/stores/styles_store.dart';
import 'data/stores/usage_store.dart';
import 'data/stores/ecopay_calculator_store.dart';
import 'data/stores/project_store.dart';
import 'data/stores/update_store.dart';
import 'data/stores/user_prefs_store.dart';
import 'core/theme/app_theme.dart';

class ShiftAiApp extends StatefulWidget {
  const ShiftAiApp({super.key});

  @override
  State<ShiftAiApp> createState() => _ShiftAiAppState();
}

class _ShiftAiAppState extends State<ShiftAiApp> {
  late final PersistenceService _persistence;
  late final ApiKeysStore _apiKeysStore;
  late final ConversationStore _conversationStore;
  late final AppSettingsStore _appSettingsStore;
  late final ProjectStore _projectStore;
  late final UserPrefsStore _userPrefsStore;
  late final ArtifactPanelStore _artifactPanelStore;
  late final MemoryStore _memoryStore;
  late final StylesStore _stylesStore;
  late final UsageStore _usageStore;
  late final UpdateStore _updateStore;
  late final ShiftBackend _backend;
  late final AccountStore _accountStore;

  @override
  void initState() {
    super.initState();
    _persistence = PersistenceService();
    _apiKeysStore = ApiKeysStore(persistence: _persistence)..load();
    // The selector decides per message: live provider calls when the user
    // has added an API key, the fully-functional mock otherwise. Nothing
    // else in the app branches on which one is active.
    final chatService = ChatServiceSelector(
      keys: _apiKeysStore,
      // Both need the asset store to reuse an image the user generated in an
      // earlier session: the in-memory bytes are gone by then, and only the
      // asset id survives in the transcript.
      real: RealChatService(
        keys: _apiKeysStore,
        loadAsset: _persistence.loadAsset,
        // Closures rather than the store itself, so the turn layer depends on
        // two questions instead of on an account object. They are read when a
        // turn runs, which is always after `initState` has finished, so the
        // late field below is assigned by then.
        //
        // The first steers routing: a member whose plan covers Anthropic is
        // offered Anthropic even with no key of their own, which is the whole
        // point. The second pays for the call.
        managedProviders: () => _accountStore.spendableProviders,
        managedAccess: (provider) => _accountStore.managedAccess(provider),
      ),
      mock: MockChatService(loadAsset: _persistence.loadAsset),
      // The same question the live backend asks, asked one layer earlier.
      // Without it the selector went by stored keys alone, so a member whose
      // plan covered everything never reached the live service at all — every
      // turn was the simulation, under a Settings card reporting the proxy
      // working, because the proxy *was* working and nothing called it.
      managedProviders: () => _accountStore.spendableProviders,
    );
    _artifactPanelStore = ArtifactPanelStore();
    _memoryStore = MemoryStore(persistence: _persistence)..load();
    _stylesStore = StylesStore(persistence: _persistence)..load();
    _usageStore = UsageStore(persistence: _persistence)..load();
    _conversationStore = ConversationStore(
      chatService: chatService,
      persistence: _persistence,
    )
      ..onArtifactCreated = _artifactPanelStore.open
      // Extract durable facts from each user turn into cross-chat memory.
      ..onUserTurnComplete = ((userText) {
        for (final fact in MemoryService.extractFacts(userText)) {
          _memoryStore.addFact(fact);
        }
      })
      ..load();
    _appSettingsStore = AppSettingsStore(persistence: _persistence)..load();
    _projectStore = ProjectStore(persistence: _persistence)..load();
    _userPrefsStore = UserPrefsStore(persistence: _persistence)..load();
    // Reads the running version and the stored check state, then looks for a
    // newer release once the first frame is up — never on the boot path.
    _updateStore = UpdateStore(persistence: _persistence);
    _updateStore.load().then((_) => _updateStore.checkIfDue());

    // The one place that knows which backend is in use. Everything above this
    // line talks to `ShiftBackend` and cannot tell — enforced by
    // `tool/scan_backend_boundary.py`, which allows the concrete names only
    // here.
    //
    // No configuration compiled in means `NoBackend`, which is not a failure
    // state: the app runs on keys kept on the device exactly as it always has,
    // and the public demo has no account at all.
    final config = BackendConfig.fromEnvironment();
    _backend = config == null
        ? NoBackend()
        : SupabaseBackend(
            config: config,
            loadStoredSession: () async =>
                ShiftSession.fromJson(await _persistence.loadSession()),
            onSessionChanged: (session) =>
                _persistence.saveSession(session?.toJson()),
          );
    _accountStore =
        AccountStore(backend: _backend, persistence: _persistence)..restore();
  }

  @override
  void dispose() {
    _backend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // Not a store, but the asset store behind it is how generated media
        // survives a reload — the audio card reads spoken voiceovers back
        // from it the same way images are re-read.
        Provider<PersistenceService>.value(value: _persistence),
        ChangeNotifierProvider.value(value: _conversationStore),
        ChangeNotifierProvider.value(value: _appSettingsStore),
        ChangeNotifierProvider(create: (_) => EcopayCalculatorStore()),
        ChangeNotifierProvider.value(value: _artifactPanelStore),
        ChangeNotifierProvider.value(value: _projectStore),
        ChangeNotifierProvider.value(value: _userPrefsStore),
        ChangeNotifierProvider.value(value: _memoryStore),
        ChangeNotifierProvider.value(value: _stylesStore),
        ChangeNotifierProvider.value(value: _usageStore),
        ChangeNotifierProvider.value(value: _apiKeysStore),
        ChangeNotifierProvider.value(value: _updateStore),
        ChangeNotifierProvider.value(value: _accountStore),
      ],
      child: Consumer<AppSettingsStore>(
        builder: (context, settings, _) {
          return MaterialApp(
            title: 'SHIFT AI',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: settings.themeMode,
            home: const HomeShell(),
          );
        },
      ),
    );
  }
}
