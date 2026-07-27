import 'package:flutter/material.dart';

import '../../data/models/membership_tier.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';

class PayoutStreamCard extends StatelessWidget {
  final PayoutStream stream;

  const PayoutStreamCard({super.key, required this.stream});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(stream.name, style: theme.textTheme.titleMedium),
          Text(
            stream.role,
            style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(stream.description, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
