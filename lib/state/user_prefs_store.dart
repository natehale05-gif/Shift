import 'package:flutter/foundation.dart';

import '../services/persistence_service.dart';

/// The user's global personalization — what to call them, what they do, the
/// traits SHIFT AI should have, a response style, and standing custom
/// instructions — folded into every turn's system prompt.
class UserPrefsStore extends ChangeNotifier {
  final PersistenceService persistence;

  String _nickname = '';
  String _role = '';
  String _traits = '';
  // normal | concise | explanatory | formal
  String _responseStyle = 'normal';
  String _customInstructions = '';

  UserPrefsStore({required this.persistence});

  String get nickname => _nickname;
  String get role => _role;
  String get traits => _traits;
  String get responseStyle => _responseStyle;
  String get customInstructions => _customInstructions;

  /// Migrates the older concise/balanced/detailed values onto the named set.
  static String _normalizeStyle(String value) => switch (value) {
        'balanced' => 'normal',
        'detailed' => 'explanatory',
        'normal' || 'concise' || 'explanatory' || 'formal' => value,
        _ => 'normal',
      };

  Future<void> load() async {
    final prefs = await persistence.loadUserPrefs();
    _nickname = prefs['nickname'] as String? ?? '';
    _role = prefs['role'] as String? ?? '';
    _traits = prefs['traits'] as String? ?? '';
    _responseStyle =
        _normalizeStyle(prefs['responseStyle'] as String? ?? 'normal');
    _customInstructions = prefs['customInstructions'] as String? ?? '';
    notifyListeners();
  }

  void setNickname(String value) {
    _nickname = value;
    notifyListeners();
    _persist();
  }

  void setRole(String value) {
    _role = value;
    notifyListeners();
    _persist();
  }

  void setTraits(String value) {
    _traits = value;
    notifyListeners();
    _persist();
  }

  void setResponseStyle(String value) {
    _responseStyle = _normalizeStyle(value);
    notifyListeners();
    _persist();
  }

  void setCustomInstructions(String value) {
    _customInstructions = value;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() => persistence.saveUserPrefs({
        'nickname': _nickname,
        'role': _role,
        'traits': _traits,
        'responseStyle': _responseStyle,
        'customInstructions': _customInstructions,
      });
}
