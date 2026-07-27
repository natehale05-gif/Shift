/// The ClubPay payout-rate level. Named the same as the site's own
/// Bronze/Silver/Gold/Platinum tiers, but this is a distinct axis from the
/// purchase tiers in [MembershipTier] — the source copy never states a
/// mapping between "which purchase gets you which payout rate," so this app
/// treats them as two independent selectors rather than inventing a link.
enum PayoutRateLevel {
  bronze(0.05, 'Bronze', '5%'),
  silver(0.10, 'Silver', '10%'),
  gold(0.15, 'Gold', '15%'),
  platinum(0.20, 'Platinum', '20%');

  final double rate;
  final String label;
  final String rateLabel;

  const PayoutRateLevel(this.rate, this.label, this.rateLabel);
}

enum GrowthAssumption {
  conservative(1.01, 'Conservative'),
  moderate(1.03, 'Moderate'),
  aggressive(1.06, 'Aggressive');

  /// Assumed month-over-month multiplier applied to the ecosystem this
  /// projection's earnings scale with. Purely illustrative.
  final double monthlyMultiplier;
  final String label;

  const GrowthAssumption(this.monthlyMultiplier, this.label);
}

/// Illustrative-only, purely client-side EcoPay earnings projection. No real
/// financial data backs this — see [PayoutStream] and the disclaimer shown
/// alongside every result this produces.
class EcopayProjection {
  /// Assumed average dollar value the ecosystem attributes per referral/
  /// content-driven sale each month, before the payout-rate percentage.
  static const double _baseValuePerReferral = 50.0;

  final PayoutRateLevel level;
  final int monthlyPace;
  final GrowthAssumption growth;

  const EcopayProjection({
    required this.level,
    required this.monthlyPace,
    required this.growth,
  });

  /// Monthly (not cumulative) illustrative earnings for months 1..[months].
  List<double> monthlyEarnings({int months = 36}) {
    return List.generate(months, (i) {
      final month = i + 1;
      final growthFactor = _pow(growth.monthlyMultiplier, month);
      return monthlyPace * _baseValuePerReferral * level.rate * growthFactor;
    });
  }

  /// Running cumulative total across months 1..[months].
  List<double> cumulativeEarnings({int months = 36}) {
    final monthly = monthlyEarnings(months: months);
    var running = 0.0;
    return monthly.map((v) {
      running += v;
      return running;
    }).toList();
  }

  static double _pow(double base, int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= base;
    }
    return result;
  }
}
