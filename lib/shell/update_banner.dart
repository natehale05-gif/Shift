import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
import '../core/platform/open_url.dart';
import '../core/update/update_installer.dart' show InstallMode;
import '../data/update_store.dart';

/// A one-line strip above the shell when a newer release exists.
///
/// Dismissal is per-version, so "not now" once does not silence every future
/// update. Renders nothing in a browser, where there is no stale copy to
/// replace.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UpdateStore>();
    if (!store.shouldPrompt) return const SizedBox.shrink();

    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final release = store.latest!;

    // A download already paid for is not dismissible — there would be nothing
    // left to bring it back.
    final dismissible = store.status == UpdateStatus.available ||
        store.status == UpdateStatus.manualRequired;

    return Material(
      color: c.accentWash,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.xs,
        ),
        child: Row(
          children: [
            Icon(Icons.arrow_circle_down_rounded, size: 18, color: c.accent),
            const SizedBox(width: Space.sm),
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
                  UpdateStatus.openedPage =>
                    'SHIFT AI ${release.tag} is on the release page — '
                        'download it there.',
                  UpdateStatus.manualRequired =>
                    'SHIFT AI ${release.tag} is available — this copy is '
                        'installed system-wide, so install it from GitHub.',
                  _ => 'SHIFT AI ${release.tag} is available.',
                },
                style: text.bodySmall?.copyWith(color: c.text),
              ),
            ),
            if (store.status == UpdateStatus.downloading)
              SizedBox(
                width: 60,
                child: LinearProgressIndicator(
                  value: store.progress > 0 ? store.progress : null,
                  backgroundColor: c.surfaceSunken,
                  color: c.accent,
                ),
              )
            else if (store.status == UpdateStatus.readyToRestart)
              _Action('Restart now', store.restartAndUpdate, c)
            else if (store.status == UpdateStatus.manualRequired)
              _Action('Get it', () => openUrl(release.pageUrl), c)
            else if (store.status == UpdateStatus.available)
              _Action(
                store.mode == InstallMode.handOffToPage ? 'Open it' : 'Get it',
                store.install,
                c,
              ),
            if (dismissible)
              ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: kMinTouchTarget,
                  minHeight: kMinTouchTarget,
                ),
                child: IconButton(
                  tooltip: 'Dismiss',
                  onPressed: store.dismiss,
                  icon: Icon(Icons.close_rounded, size: 18, color: c.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final ShiftColors colors;

  const _Action(this.label, this.onPressed, this.colors);

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: kMinTouchTarget),
        child: TextButton(
          onPressed: onPressed,
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: colors.accent),
          ),
        ),
      );
}
