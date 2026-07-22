import 'package:flutter/foundation.dart';

import '../services/persistence_service.dart';

/// A demo-only usage counter, modelled on Claude's plan-limit indicator. It
/// counts messages sent per day against an illustrative cap and rolls over at
/// midnight. Purely cosmetic — nothing is metered or charged.
class UsageStore extends ChangeNotifier {
  final PersistenceService persistence;

  /// Illustrative daily message cap.
  static const int dailyCap = 30;

  int _count = 0;
  String _day = _todayKey();

  UsageStore({required this.persistence});

  int get used => _count;
  int get cap => dailyCap;
  int get remaining => (dailyCap - _count).clamp(0, dailyCap);
  double get fraction => (_count / dailyCap).clamp(0.0, 1.0);

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  Future<void> load() async {
    final blob = await persistence.loadUsageCounter();
    _day = blob['day'] as String? ?? _todayKey();
    _count = blob['count'] as int? ?? 0;
    _rolloverIfNeeded();
    notifyListeners();
  }

  void _rolloverIfNeeded() {
    final today = _todayKey();
    if (_day != today) {
      _day = today;
      _count = 0;
    }
  }

  /// Records one sent message (rolling over the day first).
  void recordMessage() {
    _rolloverIfNeeded();
    _count += 1;
    notifyListeners();
    _persist();
  }

  Future<void> _persist() =>
      persistence.saveUsageCounter({'day': _day, 'count': _count});
}
