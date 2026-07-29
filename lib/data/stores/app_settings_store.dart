import 'package:flutter/material.dart';

import '../models/membership_tier.dart';
import '../persistence/persistence_service.dart';

/// App-wide settings: theme mode and the demo-only "selected membership
/// tier" (never a real purchase — see [MembershipTier]).
class AppSettingsStore extends ChangeNotifier {
  final PersistenceService persistence;

  ThemeMode _themeMode = ThemeMode.system;
  String? _selectedTierId;
  bool _showUsage = true;

  AppSettingsStore({required this.persistence});

  ThemeMode get themeMode => _themeMode;

  /// Whether to show the model/token usage readout under assistant replies.
  bool get showUsage => _showUsage;

  MembershipTier? get selectedTier {
    if (_selectedTierId == null) return null;
    try {
      return MembershipTier.all.firstWhere((t) => t.id == _selectedTierId);
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    final stored = await persistence.loadThemeMode();
    _themeMode = switch (stored) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _selectedTierId = await persistence.loadSelectedTier();
    _showUsage = await persistence.loadShowUsage() ?? true;
    notifyListeners();
  }

  void setThemeMode(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    persistence.saveThemeMode(mode.name);
  }

  void setShowUsage(bool value) {
    _showUsage = value;
    notifyListeners();
    persistence.saveShowUsage(value);
  }

  /// Demo only: records which membership tier the user "simulated" picking.
  /// Never triggers a real purchase, charge, or credit grant.
  void simulateSelectTier(String tierId) {
    _selectedTierId = tierId;
    notifyListeners();
    persistence.saveSelectedTier(tierId);
  }

  void clearSelectedTier() {
    _selectedTierId = null;
    notifyListeners();
    persistence.saveSelectedTier(null);
  }
}
