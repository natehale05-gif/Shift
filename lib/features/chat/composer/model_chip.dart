


import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/stores/api_keys_store.dart';
import '../../../services/providers/provider_capability.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


/// Claude-style composer: a single rounded card holding the text field with
/// a row of controls beneath it — an attach button, a model chip, and a
/// circular purple send button.
class ModelChip extends StatelessWidget {
  final String? modelPin;
  final ValueChanged<String?> onSelected;

  const ModelChip({super.key, required this.modelPin, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final keys = context.watch<ApiKeysStore>();
    final registry = keys.registry;
    final label =
        modelPin == null ? 'Auto' : registry.displayNameForModel(modelPin!);

    // Providers the user has a key for that expose chat models.
    final keyedProviders = [
      for (final d in registry.all)
        if (keys.hasKey(d.id) && d.modelsFor(ProviderCapability.chat).isNotEmpty)
          d,
    ];

    return PopupMenuButton<String>(
      tooltip:
          'Choose a model — Auto lets the middleware AI route each '
          'request.',
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      onSelected: (value) => onSelected(value == 'auto' ? null : value),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'auto',
          checked: modelPin == null,
          child: const Text('Auto (recommended)'),
        ),
        for (final provider in keyedProviders) ...[
          PopupMenuItem<String>(
            enabled: false,
            height: 32,
            child: Text(
              provider.displayName.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
                letterSpacing: 0.5,
              ),
            ),
          ),
          for (final model in provider.modelsFor(ProviderCapability.chat))
            CheckedPopupMenuItem(
              value: model.id,
              checked: modelPin == model.id,
              child: Text(model.displayName),
            ),
        ],
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more_rounded,
              size: 14,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-conversation style picker in the composer. "Default" defers to the
/// global setting; picking a built-in or custom style overrides it for the
/// turns that follow. "Create style…" adds a new custom style.
