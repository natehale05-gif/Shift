import 'package:flutter/foundation.dart';

import '../persistence/persistence_service.dart';

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
  // The new-chat greeting shown last time, so the next one can differ. Stored
  // rather than held in memory because most repeats a user would notice happen
  // across launches, not within one.
  String _lastGreeting = '';

  UserPrefsStore({required this.persistence});

  String get nickname => _nickname;
  String get role => _role;
  String get traits => _traits;
  String get responseStyle => _responseStyle;
  String get customInstructions => _customInstructions;
  String get lastGreeting => _lastGreeting;

  /// Migrates the older concise/balanced/detailed values onto the named set.
  ///
  /// Anything else is kept as-is: this setting also holds a *custom* style's
  /// id, which is the only place one is chosen now that the composer's Style
  /// menu is gone. It used to collapse every unrecognised value to 'normal',
  /// which would silently discard a custom style the moment it was selected.
  /// An id whose style has since been deleted resolves to no clause at all,
  /// so a stale value degrades to Normal rather than breaking.
  static String _normalizeStyle(String value) => switch (value) {
        'balanced' => 'normal',
        'detailed' => 'explanatory',
        '' => 'normal',
        _ => value,
      };

  Future<void> load() async {
    final prefs = await persistence.loadUserPrefs();
    _nickname = prefs['nickname'] as String? ?? '';
    _role = prefs['role'] as String? ?? '';
    _traits = prefs['traits'] as String? ?? '';
    _responseStyle =
        _normalizeStyle(prefs['responseStyle'] as String? ?? 'normal');
    _customInstructions = prefs['customInstructions'] as String? ?? '';
    _lastGreeting = prefs['lastGreeting'] as String? ?? '';
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

  /// Records the greeting just shown. Deliberately does **not** notify: the
  /// only reader is the next new chat, and rebuilding the screen that just
  /// displayed it would be a rebuild for nothing.
  void setLastGreeting(String value) {
    if (value == _lastGreeting) return;
    _lastGreeting = value;
    _persist();
  }

  Future<void> _persist() => persistence.saveUserPrefs({
        'nickname': _nickname,
        'role': _role,
        'traits': _traits,
        'responseStyle': _responseStyle,
        'customInstructions': _customInstructions,
        'lastGreeting': _lastGreeting,
      });
}
