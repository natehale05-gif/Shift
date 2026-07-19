import 'package:flutter/material.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

/// A prominent warning banner used anywhere payout/earnings figures are
/// shown. Mirrors the real site's own calculator disclaimer — nothing on
/// these screens represents a real transaction or guaranteed outcome.
class DisclaimerBanner extends StatelessWidget {
  final String text;

  const DisclaimerBanner({
    super.key,
    this.text =
        'Illustrative example only. Not a representation of typical or expected earnings. Most participants earn modest amounts or nothing. This app simulates all figures locally — no real purchases, payouts, or transactions occur.',
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.warningSurface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: colors.warningText),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.warningText,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
