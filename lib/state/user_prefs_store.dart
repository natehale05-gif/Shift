import 'package:flutter/foundation.dart';

import '../services/persistence_service.dart';

/// The user's global personalization — nickname, response style, and
/// standing custom instructions — folded into every turn's system prompt.
/// This is the app's "memory/personalization" layer.
class UserPrefsStore extends ChangeNotifier {
  final PersistenceService persistence;

  String _nickname = '';
  String _responseStyle = 'balanced'; // concise | balanced | detailed
  String _customInstructions = '';

  UserPrefsStore({required this.persistence});

  String get nickname => _nickname;
  String get responseStyle => _responseStyle;
  String get customInstructions => _customInstructions;

  Future<void> load() async {
    final prefs = await persistence.loadUserPrefs();
    _nickname = prefs['nickname'] as String? ?? '';
    _responseStyle = prefs['responseStyle'] as String? ?? 'balanced';
    _customInstructions = prefs['customInstructions'] as String? ?? '';
    notifyListeners();
  }

  void setNickname(String value) {
    _nickname = value;
    notifyListeners();
    _persist();
  }

  void setResponseStyle(String value) {
    _responseStyle = value;
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
        'responseStyle': _responseStyle,
        'customInstructions': _customInstructions,
      });
}
