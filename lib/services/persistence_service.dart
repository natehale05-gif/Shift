import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/conversation.dart';

/// Thin wrapper over [SharedPreferences] (backed by browser `localStorage`
/// on web) — the only persistence in this app, since there's no backend and
/// no auth yet.
class PersistenceService {
  static const _conversationsKey = 'shift_ai.conversations.v1';
  static const _themeModeKey = 'shift_ai.theme_mode.v1';
  static const _selectedTierKey = 'shift_ai.selected_tier.v1';
  static const maxStoredConversations = 50;

  Future<List<Conversation>> loadConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_conversationsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveConversations(List<Conversation> conversations) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = conversations.length > maxStoredConversations
        ? (conversations..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)))
            .take(maxStoredConversations)
            .toList()
        : conversations;
    await prefs.setString(
      _conversationsKey,
      jsonEncode(trimmed.map((c) => c.toJson()).toList()),
    );
  }

  Future<String?> loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_themeModeKey);
  }

  Future<void> saveThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, mode);
  }

  Future<String?> loadSelectedTier() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedTierKey);
  }

  Future<void> saveSelectedTier(String? tierId) async {
    final prefs = await SharedPreferences.getInstance();
    if (tierId == null) {
      await prefs.remove(_selectedTierKey);
    } else {
      await prefs.setString(_selectedTierKey, tierId);
    }
  }
}
