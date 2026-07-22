import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_shell.dart';
import 'services/memory_service.dart';
import 'services/mock_chat_service.dart';
import 'services/persistence_service.dart';
import 'services/real_chat_service.dart';
import 'state/api_keys_store.dart';
import 'state/app_settings_store.dart';
import 'state/artifact_panel_store.dart';
import 'state/conversation_store.dart';
import 'state/memory_store.dart';
import 'state/styles_store.dart';
import 'state/usage_store.dart';
import 'state/ecopay_calculator_store.dart';
import 'state/project_store.dart';
import 'state/user_prefs_store.dart';
import 'theme/app_theme.dart';

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
      real: RealChatService(keys: _apiKeysStore),
      mock: MockChatService(),
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
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
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
