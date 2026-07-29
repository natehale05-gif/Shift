import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/platform/open_url.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/update/update_check.dart';
import '../../data/stores/update_store.dart';

/// The mirror of `_GetTheAppCard`: that one points browser users at the
/// downloads, this one keeps a downloaded copy current. Each hides itself on
/// the other's platform.
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UpdateStore>();
    if (!store.enabled) return const SizedBox.shrink();

    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    final text = Theme.of(context).textTheme;
    final busy = store.status == UpdateStatus.checking;

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
          Text('Updates', style: text.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Text(
            store.currentVersion.isEmpty
                ? 'SHIFT AI'
                : 'SHIFT AI ${store.currentVersion}',
            style: text.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(_statusLine(store), style: text.bodySmall),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : store.checkNow,
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Check now'),
              ),
              if (store.status == UpdateStatus.available)
                FilledButton.icon(
                  onPressed: () => openUrl(
                      store.latest?.pageUrl ?? UpdateCheck.releasesPage),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open release page'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _statusLine(UpdateStore store) => switch (store.status) {
        UpdateStatus.idle => 'Checked automatically once a day.',
        UpdateStatus.checking => 'Checking for updates…',
        UpdateStatus.upToDate => "You're on the latest version.",
        UpdateStatus.available =>
          'Version ${store.latest?.tag ?? ''} is available.',
        // Never "you're up to date" — the app does not know that it is.
        UpdateStatus.failed =>
          "Couldn't check right now. You may be offline, or there may be no "
              'published release yet.',
      };
}
