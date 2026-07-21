import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/conversation.dart';
import '../models/project.dart';
import 'storage/storage_backend.dart';

/// The app's persistence layer, backed by IndexedDB (via idb_shim) so
/// conversations, artifacts, and generated-image assets aren't squeezed
/// into localStorage's ~5MB quota. The public API predates the IndexedDB
/// move — callers never changed.
///
/// On first run after the migration shipped, any data the earlier
/// localStorage (shared_preferences) build stored is copied over once; the
/// old values are left in place as a backup.
class PersistenceService {
  static const _conversationsKeyV1 = 'shift_ai.conversations.v1';
  static const _themeModeKey = 'shift_ai.theme_mode.v1';
  static const _showUsageKey = 'shift_ai.show_usage.v1';
  static const _selectedTierKey = 'shift_ai.selected_tier.v1';
  static const _projectsKey = 'shift_ai.projects.v1';
  static const _activeProjectKey = 'shift_ai.active_project.v1';
  static const _memoryKey = 'shift_ai.memory.v1';
  static const _userPrefsKey = 'shift_ai.user_prefs.v1';
  static const _migratedFlagKey = 'shift_ai.migrated_to_idb.v1';
  static const maxStoredConversations = 50;

  /// Generated images kept before oldest are pruned.
  static const maxStoredAssets = 40;

  final StorageBackend _backend;
  Future<void>? _migration;

  PersistenceService({StorageBackend? backend})
      : _backend = backend ?? StorageBackend();

  /// One-shot localStorage → IndexedDB copy, run lazily before the first
  /// read. Failures (e.g. no shared_preferences in a bare test harness)
  /// just skip migration — there'd be nothing to migrate there anyway.
  Future<void> _ensureMigrated() => _migration ??= _migrate();

  Future<void> _migrate() async {
    try {
      if (await _backend.getKv(_migratedFlagKey) == 'true') return;
      final prefs = await SharedPreferences.getInstance();

      final conversationsRaw = prefs.getString(_conversationsKeyV1);
      if (conversationsRaw != null && conversationsRaw.isNotEmpty) {
        try {
          final list = jsonDecode(conversationsRaw) as List<dynamic>;
          for (final entry in list) {
            final map = entry as Map<String, dynamic>;
            await _backend.putConversationJson(
              map['id'] as String,
              jsonEncode(map),
            );
          }
        } catch (_) {
          // Corrupt old blob: nothing worth carrying over.
        }
      }
      for (final key in [
        _themeModeKey,
        _selectedTierKey,
        _projectsKey,
        _userPrefsKey,
      ]) {
        final value = prefs.getString(key);
        if (value != null) await _backend.putKv(key, value);
      }
      await _backend.putKv(_migratedFlagKey, 'true');
    } catch (_) {
      // shared_preferences unavailable (plain unit-test harness):
      // proceed with an empty IndexedDB.
    }
  }

  // --- conversations ---

  Future<List<Conversation>> loadConversations() async {
    await _ensureMigrated();
    final jsonStrings = await _backend.getAllConversationJson();
    final conversations = <Conversation>[];
    for (final raw in jsonStrings) {
      try {
        conversations
            .add(Conversation.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Skip an unreadable record rather than losing the whole history.
      }
    }
    conversations.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return conversations;
  }

  /// Persists a single conversation — the common path while chatting.
  Future<void> saveConversation(Conversation conversation) async {
    await _ensureMigrated();
    await _backend.putConversationJson(
      conversation.id,
      jsonEncode(conversation.toJson()),
    );
  }

  Future<void> deleteConversation(String id) async {
    await _ensureMigrated();
    await _backend.deleteConversation(id);
  }

  /// Bulk rewrite (clear-all, cap trimming).
  Future<void> saveConversations(List<Conversation> conversations) async {
    await _ensureMigrated();
    await _backend.clearConversations();
    final trimmed = [...conversations]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final conversation in trimmed.take(maxStoredConversations)) {
      await _backend.putConversationJson(
        conversation.id,
        jsonEncode(conversation.toJson()),
      );
    }
  }

  // --- assets (generated images etc.) ---

  Future<void> saveAsset(String id, Uint8List bytes) async {
    await _ensureMigrated();
    await _backend.putAsset(id, bytes);
    final index = await _backend.assetIndex();
    if (index.length > maxStoredAssets) {
      for (final (assetId, _) in index.take(index.length - maxStoredAssets)) {
        await _backend.deleteAsset(assetId);
      }
    }
  }

  Future<Uint8List?> loadAsset(String id) async {
    await _ensureMigrated();
    return _backend.getAsset(id);
  }

  // --- small settings (kv) ---

  Future<String?> _getKv(String key) async {
    await _ensureMigrated();
    return _backend.getKv(key);
  }

  Future<void> _putKv(String key, String value) async {
    await _ensureMigrated();
    await _backend.putKv(key, value);
  }

  Future<String?> loadThemeMode() => _getKv(_themeModeKey);

  Future<void> saveThemeMode(String mode) => _putKv(_themeModeKey, mode);

  Future<bool?> loadShowUsage() async {
    final raw = await _getKv(_showUsageKey);
    return raw == null ? null : raw == 'true';
  }

  Future<void> saveShowUsage(bool value) =>
      _putKv(_showUsageKey, value.toString());

  Future<String?> loadSelectedTier() => _getKv(_selectedTierKey);

  Future<void> saveSelectedTier(String? tierId) async {
    await _ensureMigrated();
    if (tierId == null) {
      await _backend.deleteKv(_selectedTierKey);
    } else {
      await _backend.putKv(_selectedTierKey, tierId);
    }
  }

  Future<List<Project>> loadProjects() async {
    final raw = await _getKv(_projectsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Project.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveProjects(List<Project> projects) => _putKv(
        _projectsKey,
        jsonEncode(projects.map((p) => p.toJson()).toList()),
      );

  /// Memory blob: `{enabled: bool, entries: [...]}`.
  Future<Map<String, dynamic>> loadMemory() async {
    final raw = await _getKv(_memoryKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  Future<void> saveMemory(Map<String, dynamic> value) =>
      _putKv(_memoryKey, jsonEncode(value));

  Future<String?> loadActiveProject() => _getKv(_activeProjectKey);

  Future<void> saveActiveProject(String? id) async {
    await _ensureMigrated();
    if (id == null) {
      await _backend.deleteKv(_activeProjectKey);
    } else {
      await _backend.putKv(_activeProjectKey, id);
    }
  }

  /// Provider API keys (BYOK). Stored in this browser's IndexedDB only —
  /// there is no backend to send them to.
  Future<String?> loadApiKey(String keyName) => _getKv(keyName);

  Future<void> saveApiKey(String keyName, String? value) async {
    await _ensureMigrated();
    if (value == null || value.isEmpty) {
      await _backend.deleteKv(keyName);
    } else {
      await _backend.putKv(keyName, value);
    }
  }

  Future<Map<String, dynamic>> loadUserPrefs() async {
    final raw = await _getKv(_userPrefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveUserPrefs(Map<String, dynamic> value) =>
      _putKv(_userPrefsKey, jsonEncode(value));
}
