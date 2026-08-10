import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/api_keys_store.dart';
import '../../providers/registry.dart';
import 'provider_key_field.dart';

/// Where a key goes in.
///
/// Until this existed the app answered every message with "Add a key in
/// Settings, or start a plan" — naming a place that did not exist. The
/// sentence was honest about the state and dishonest about the remedy, and it
/// meant the app could not answer anything at all.
///
/// The list is built from [kProviders] rather than from a second hardcoded
/// list. The registry already carries the label, the URL where a key is
/// obtained, the shape a key of that kind takes, and what it unlocks — so a
/// provider added there appears here with no further work, and the two cannot
/// drift apart.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final keys = context.watch<ApiKeysStore>();

    return Scaffold(
      backgroundColor: c.ground,
      appBar: AppBar(
        backgroundColor: c.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text('Settings', style: text.headlineSmall),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(Space.lg),
              children: [
                Text('Provider keys', style: text.titleMedium),
                const SizedBox(height: Space.xs),
                Text(
                  'Add a key and SHIFT talks to that provider directly. '
                  'Nothing is sent through a server.',
                  style: text.bodySmall?.copyWith(color: c.textMuted),
                ),
                const SizedBox(height: Space.md),

                // Said on screen rather than in a document nobody opens. This
                // is the honest argument for the subscription — there the key
                // is held server-side and never reaches the device — and it
                // would be a bad trade to hide it in order to make this path
                // look better than it is.
                Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  padding: const EdgeInsets.all(Space.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline_rounded,
                          size: 18, color: c.textMuted),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          'Keys are stored on this device only. In a browser '
                          'that means the browser\'s own storage, which any '
                          'script on this site could read. A subscription will '
                          'keep keys on the server instead.',
                          style:
                              text.bodySmall?.copyWith(color: c.textMuted),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.lg),

                for (final provider in kProviders) ...[
                  ProviderKeyField(
                    provider: provider,
                    saved: keys.masked(provider.id),
                    onSave: (value) => keys.set(provider.id, value),
                    onRemove: () => keys.remove(provider.id),
                    readKey: () => keys.get(provider.id),
                  ),
                  const SizedBox(height: Space.md),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
