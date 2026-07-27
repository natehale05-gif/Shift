import 'package:flutter/foundation.dart';

import '../models/ecopay_projection.dart';

/// Pure UI state for the illustrative EcoPay calculator — inputs only, all
/// math lives in [EcopayProjection].
class EcopayCalculatorStore extends ChangeNotifier {
  PayoutRateLevel _level = PayoutRateLevel.silver;
  int _monthlyPace = 4;
  GrowthAssumption _growth = GrowthAssumption.moderate;

  PayoutRateLevel get level => _level;
  int get monthlyPace => _monthlyPace;
  GrowthAssumption get growth => _growth;

  EcopayProjection get projection => EcopayProjection(
        level: _level,
        monthlyPace: _monthlyPace,
        growth: _growth,
      );

  void setLevel(PayoutRateLevel level) {
    _level = level;
    notifyListeners();
  }

  void setMonthlyPace(int pace) {
    _monthlyPace = pace;
    notifyListeners();
  }

  void setGrowth(GrowthAssumption growth) {
    _growth = growth;
    notifyListeners();
  }
}
