import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/platform/open_url.dart';
import '../../core/update/update_check.dart';
import '../../core/update/update_installer.dart' show InstallMode;
import '../../data/update_store.dart';

/// Which version is running, and whether it is the newest one published.
///
/// Renders nothing in a browser: this build registers no service worker, so a
/// reload is already the latest deploy and there is nothing to report.
class UpdateCard extends StatelessWidget {
  const UpdateCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<UpdateStore>();
    if (!store.enabled) return const SizedBox.shrink();

    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final busy = store.status == UpdateStatus.checking;

    return Container(
      margin: const EdgeInsets.only(bottom: Space.lg),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Updates', style: text.titleMedium?.copyWith(color: c.text)),
          const SizedBox(height: Space.xxs),
          Text(
            store.currentVersion.isEmpty
                ? 'SHIFT AI'
                : 'SHIFT AI ${store.currentVersion}',
            style: text.bodySmall?.copyWith(color: c.textMuted),
          ),
          const SizedBox(height: Space.sm),
          Text(
            _statusLine(store),
            style: text.bodySmall?.copyWith(
              color: store.status == UpdateStatus.failed ? c.danger : c.text,
            ),
          ),

          if (store.status == UpdateStatus.downloading) ...[
            const SizedBox(height: Space.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.xs),
              child: LinearProgressIndicator(
                value: store.progress > 0 ? store.progress : null,
                backgroundColor: c.surfaceSunken,
                color: c.accent,
              ),
            ),
          ],

          // Offered only where it means something. On Android the app never
          // installs anything itself, so a switch promising automatic installs
          // would be a control that cannot do what it says.
          if (store.mode == InstallMode.replaceAndRelaunch ||
              store.mode == InstallMode.handOffToSystem) ...[
            const SizedBox(height: Space.md),
            // A row rather than a `SwitchListTile`: a ListTile paints its ink
            // on the nearest Material, which this card's own decoration sits
            // in front of, so the splash would be invisible — the framework
            // asserts on exactly that, and it was right.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Install updates automatically',
                          style: text.bodyMedium?.copyWith(color: c.text)),
                      const SizedBox(height: Space.xxs),
                      Text(
                        store.mode == InstallMode.replaceAndRelaunch
                            ? 'Downloads new versions in the background and '
                                'applies them the next time you open the app.'
                            : 'Downloads new versions in the background. macOS '
                                'asks you to confirm the install.',
                        style: text.bodySmall?.copyWith(color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minWidth: kMinTouchTarget,
                    minHeight: kMinTouchTarget,
                  ),
                  child: Switch(
                    value: store.autoInstall,
                    activeThumbColor: c.accent,
                    onChanged: store.setAutoInstall,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: Space.sm),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinTouchTarget),
                child: TextButton(
                  onPressed: busy ? null : store.checkNow,
                  child: Text(busy ? 'Checking…' : 'Check now',
                      style: text.labelLarge?.copyWith(color: c.accent)),
                ),
              ),
              if (store.status == UpdateStatus.readyToRestart)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinTouchTarget),
                  child: FilledButton(
                    onPressed: store.restartAndUpdate,
                    child: const Text('Restart to finish'),
                  ),
                ),
              if (store.status == UpdateStatus.available)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinTouchTarget),
                  child: FilledButton(
                    onPressed: store.install,
                    child: Text(store.mode == InstallMode.handOffToPage
                        ? 'Open the download'
                        : 'Download it'),
                  ),
                ),
              if (store.status == UpdateStatus.manualRequired)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinTouchTarget),
                  child: FilledButton(
                    onPressed: () => openUrl(_page(store)),
                    child: const Text('Get it from GitHub'),
                  ),
                ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinTouchTarget),
                child: TextButton(
                  onPressed: () => openUrl(_page(store)),
                  child: Text('Release notes',
                      style: text.labelLarge?.copyWith(color: c.textMuted)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _page(UpdateStore store) =>
      store.latest?.pageUrl ?? UpdateCheck.releasesPage;

  String _statusLine(UpdateStore store) => switch (store.status) {
        UpdateStatus.idle => 'Checked automatically once a day.',
        UpdateStatus.checking => 'Checking for updates…',
        UpdateStatus.upToDate => "You're on the latest version.",
        UpdateStatus.available =>
          'Version ${store.latest?.tag ?? ''} is available.',
        UpdateStatus.downloading =>
          'Downloading ${store.latest?.tag ?? 'the update'}…',
        UpdateStatus.readyToRestart =>
          '${store.latest?.tag ?? 'An update'} is ready. It is applied the '
              'next time you open the app.',
        UpdateStatus.handedOff =>
          '${store.latest?.tag ?? 'The update'} has been downloaded and the '
              'installer is open. Finish there.',
        // Android. Says what will happen next rather than implying the app is
        // doing it: installing an APK from inside the app needs a permission
        // Play prohibits, so the download and the install are $_installer's.
        UpdateStatus.openedPage =>
          '${store.latest?.tag ?? 'The update'} is on the release page, which '
              'is now open. Download it and $_installer will ask you to '
              'confirm.',
        // Says which of the two things is true — the update exists, and this
        // copy specifically cannot apply it — rather than a bare failure.
        UpdateStatus.manualRequired =>
          '${store.latest?.tag ?? 'A new version'} is available. This copy is '
              'installed system-wide, so it cannot replace itself — install '
              'the new version from GitHub.',
        // Never "you're up to date" — the app does not know that it is.
        UpdateStatus.failed =>
          "Couldn't check right now. You may be offline, or there may be no "
              'published release yet.',
      };

  static String get _installer =>
      defaultTargetPlatform == TargetPlatform.android ? 'Android' : 'your OS';
}
