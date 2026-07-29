import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/stores/update_store.dart';
import '../platform/open_url.dart';
import '../update/update_installer.dart' show InstallMode;
import '../theme/app_spacing.dart';
import '../theme/app_theme.dart';

/// A one-line strip above the whole shell when a newer release exists.
///
/// Dismissal is per-version, so saying "not now" once does not silence every
/// future update. Renders nothing on web, where the service worker already
/// swaps builds in without asking.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UpdateStore>();
    if (!store.shouldPrompt) return const SizedBox.shrink();

    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    final release = store.latest!;
    final downloading = store.status == UpdateStatus.downloading;

    return Material(
      color: colors.warningSurface,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Icon(Icons.system_update_rounded,
                size: 18, color: colors.warningText),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                switch (store.status) {
                  UpdateStatus.downloading =>
                    'Downloading SHIFT AI ${release.tag}…',
                  UpdateStatus.readyToRestart =>
                    'SHIFT AI ${release.tag} is ready — it installs next time '
                        'you open the app.',
                  UpdateStatus.handedOff =>
                    'SHIFT AI ${release.tag} downloaded. Finish in the '
                        'installer.',
                  UpdateStatus.manualRequired =>
                    'SHIFT AI ${release.tag} is available — this copy is '
                        'installed system-wide, so install it from GitHub.',
                  _ => 'SHIFT AI ${release.tag} is available.',
                },
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.warningText,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ),
            if (downloading)
              SizedBox(
                width: 60,
                child: LinearProgressIndicator(
                  value: store.progress > 0 ? store.progress : null,
                ),
              )
            else if (store.status == UpdateStatus.readyToRestart)
              TextButton(
                onPressed: store.restartAndUpdate,
                child: const Text('Restart now'),
              )
            else if (store.status == UpdateStatus.manualRequired)
              TextButton(
                onPressed: () => openUrl(release.pageUrl),
                child: const Text('Get it from GitHub'),
              )
            else if (store.status == UpdateStatus.available)
              TextButton(
                onPressed: store.mode == InstallMode.unsupported
                    ? () => openUrl(release.pageUrl)
                    : store.install,
                child: const Text('Get it'),
              ),
            // A download already paid for is not dismissible -- there would
            // be nothing left to bring it back.
            if (store.status == UpdateStatus.available ||
                store.status == UpdateStatus.manualRequired)
              IconButton(
                tooltip: 'Dismiss',
                onPressed: store.dismiss,
                icon: Icon(Icons.close_rounded,
                    size: 18, color: colors.warningText),
              ),
          ],
        ),
      ),
    );
  }
}
