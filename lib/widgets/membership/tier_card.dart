import 'package:flutter/material.dart';

import '../../models/membership_tier.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

class TierCard extends StatelessWidget {
  final MembershipTier tier;
  final bool isSelected;
  final VoidCallback onSimulateSelect;

  const TierCard({
    super.key,
    required this.tier,
    required this.isSelected,
    required this.onSimulateSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(
          color: tier.highlighted ? theme.colorScheme.primary : colors.border,
          width: tier.highlighted ? 1.5 : 1,
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tier.highlighted)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _Pill(text: 'MOST POPULAR', color: theme.colorScheme.primary),
              ),
            Text(tier.name, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(tier.priceLabel, style: theme.textTheme.displayMedium),
            Text(tier.billingNote, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.md),
            _Pill(text: tier.creditsLabel, color: colors.textSecondary),
            const SizedBox(height: AppSpacing.md),
            for (final perk in tier.perks)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_rounded, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(perk, style: theme.textTheme.bodySmall)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.tonal(
              onPressed: onSimulateSelect,
              child: Text(isSelected ? 'Selected (Demo)' : 'Simulate Selecting This Plan (Demo)'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.4),
      ),
    );
  }
}
