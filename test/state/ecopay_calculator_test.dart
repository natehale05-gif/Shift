import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/models/ecopay_projection.dart';

void main() {
  group('EcopayProjection', () {
    test('monthlyEarnings scales with payout rate level', () {
      final bronze = EcopayProjection(
        level: PayoutRateLevel.bronze,
        monthlyPace: 5,
        growth: GrowthAssumption.conservative,
      );
      final platinum = EcopayProjection(
        level: PayoutRateLevel.platinum,
        monthlyPace: 5,
        growth: GrowthAssumption.conservative,
      );

      final bronzeMonth1 = bronze.monthlyEarnings(months: 1).single;
      final platinumMonth1 = platinum.monthlyEarnings(months: 1).single;

      // Platinum (20%) should earn exactly 4x Bronze (5%) at month 1.
      expect(platinumMonth1 / bronzeMonth1, closeTo(4.0, 1e-9));
    });

    test('monthlyEarnings scales linearly with pace', () {
      final slow = EcopayProjection(
        level: PayoutRateLevel.silver,
        monthlyPace: 2,
        growth: GrowthAssumption.moderate,
      );
      final fast = EcopayProjection(
        level: PayoutRateLevel.silver,
        monthlyPace: 4,
        growth: GrowthAssumption.moderate,
      );

      final slowMonth1 = slow.monthlyEarnings(months: 1).single;
      final fastMonth1 = fast.monthlyEarnings(months: 1).single;

      expect(fastMonth1 / slowMonth1, closeTo(2.0, 1e-9));
    });

    test('zero pace produces zero earnings every month', () {
      final projection = EcopayProjection(
        level: PayoutRateLevel.gold,
        monthlyPace: 0,
        growth: GrowthAssumption.aggressive,
      );
      final monthly = projection.monthlyEarnings();
      expect(monthly.every((v) => v == 0), isTrue);
    });

    test('cumulativeEarnings is a running, non-decreasing total', () {
      final projection = EcopayProjection(
        level: PayoutRateLevel.silver,
        monthlyPace: 3,
        growth: GrowthAssumption.moderate,
      );
      final monthly = projection.monthlyEarnings(months: 12);
      final cumulative = projection.cumulativeEarnings(months: 12);

      expect(cumulative.length, 12);
      var runningTotal = 0.0;
      for (var i = 0; i < monthly.length; i++) {
        runningTotal += monthly[i];
        expect(cumulative[i], closeTo(runningTotal, 1e-9));
      }
      for (var i = 1; i < cumulative.length; i++) {
        expect(cumulative[i], greaterThanOrEqualTo(cumulative[i - 1]));
      }
    });

    test('higher growth assumption compounds to a larger later-month value', () {
      final conservative = EcopayProjection(
        level: PayoutRateLevel.silver,
        monthlyPace: 5,
        growth: GrowthAssumption.conservative,
      );
      final aggressive = EcopayProjection(
        level: PayoutRateLevel.silver,
        monthlyPace: 5,
        growth: GrowthAssumption.aggressive,
      );

      final conservativeMonth36 = conservative.monthlyEarnings(months: 36).last;
      final aggressiveMonth36 = aggressive.monthlyEarnings(months: 36).last;

      expect(aggressiveMonth36, greaterThan(conservativeMonth36));
    });
  });
}
