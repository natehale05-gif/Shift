import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/ecopay_projection.dart';
import '../../state/ecopay_calculator_store.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/disclaimer_banner.dart';

/// A purely client-side, illustrative earnings calculator mirroring the
/// real site's own "EcoPay Usage Calculator." All math runs locally in
/// [EcopayProjection] — nothing here represents a real transaction.
class EcopayCalculatorScreen extends StatelessWidget {
  const EcopayCalculatorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<EcopayCalculatorStore>();
    final currency = NumberFormat.compactCurrency(symbol: '\$');
    final monthly = store.projection.monthlyEarnings();
    final cumulative = store.projection.cumulativeEarnings();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const DisclaimerBanner(),
          const SizedBox(height: AppSpacing.lg),
          Text('EcoPay Usage Calculator', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            'Pick a payout-rate level, your pace, and a company-growth assumption to see an illustrative 36-month projection.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.xl),
          _InputsCard(store: store),
          const SizedBox(height: AppSpacing.xl),
          _ChartCard(cumulative: cumulative, currency: currency),
          const SizedBox(height: AppSpacing.xl),
          _MilestoneTable(monthly: monthly, cumulative: cumulative, currency: currency),
          const SizedBox(height: AppSpacing.xl),
          const DisclaimerBanner(),
        ],
      ),
    );
  }
}

class _InputsCard extends StatelessWidget {
  final EcopayCalculatorStore store;
  const _InputsCard({required this.store});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ClubPay payout-rate level', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final level in PayoutRateLevel.values)
                ChoiceChip(
                  label: Text('${level.label} · ${level.rateLabel}'),
                  selected: store.level == level,
                  onSelected: (_) => store.setLevel(level),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Pace · ${store.monthlyPace} referrals/month', style: Theme.of(context).textTheme.labelLarge),
          Slider(
            value: store.monthlyPace.toDouble(),
            min: 0,
            max: 20,
            divisions: 20,
            label: '${store.monthlyPace}',
            onChanged: (v) => store.setMonthlyPace(v.round()),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text('Company growth assumption', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final growth in GrowthAssumption.values)
                ChoiceChip(
                  label: Text(growth.label),
                  selected: store.growth == growth,
                  onSelected: (_) => store.setGrowth(growth),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final List<double> cumulative;
  final NumberFormat currency;
  const _ChartCard({required this.cumulative, required this.currency});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    final accent = Theme.of(context).colorScheme.primary;
    final maxY = cumulative.isEmpty ? 1.0 : cumulative.last * 1.15 + 1;

    return Container(
      height: 260,
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: LineChart(
        LineChartData(
          minX: 1,
          maxX: cumulative.length.toDouble(),
          minY: 0,
          maxY: maxY,
          gridData: const FlGridData(drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 6,
                getTitlesWidget: (value, meta) => Text('${value.round()}mo', style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 56,
                getTitlesWidget: (value, meta) => Text(currency.format(value), style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < cumulative.length; i++) FlSpot((i + 1).toDouble(), cumulative[i]),
              ],
              isCurved: true,
              color: accent,
              barWidth: 3,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: true, color: accent.withValues(alpha: 0.12)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MilestoneTable extends StatelessWidget {
  final List<double> monthly;
  final List<double> cumulative;
  final NumberFormat currency;

  const _MilestoneTable({required this.monthly, required this.cumulative, required this.currency});

  static const _milestones = [1, 6, 12, 24, 36];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1.3), 2: FlexColumnWidth(1.3)},
        children: [
          TableRow(
            decoration: BoxDecoration(color: colors.surfaceAlt),
            children: [
              _cell(context, 'Month', header: true),
              _cell(context, 'That month', header: true),
              _cell(context, 'Cumulative', header: true),
            ],
          ),
          for (final month in _milestones)
            if (month <= monthly.length)
              TableRow(
                children: [
                  _cell(context, '$month'),
                  _cell(context, currency.format(monthly[month - 1])),
                  _cell(context, currency.format(cumulative[month - 1])),
                ],
              ),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, String text, {bool header = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Text(
        text,
        style: header
            ? Theme.of(context).textTheme.labelMedium
            : Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
