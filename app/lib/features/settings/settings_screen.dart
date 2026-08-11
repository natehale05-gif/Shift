import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/agent_store.dart';
import '../../data/api_keys_store.dart';
import '../../data/artifact_store.dart';
import '../../data/conversation_store.dart';
import '../../data/kv_store.dart';
import '../../data/note_store.dart';
import '../../providers/registry.dart';
import '../chat/turn_controller.dart';
import 'erase_everything.dart';
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

                const SizedBox(height: Space.xl),
                const _EraseEverything(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The way out.
///
/// At the foot of Settings, in the danger ink, because it is the last thing
/// anyone should reach and the first thing they should be able to find when
/// they want it — handing someone the app, or leaving a shared machine.
class _EraseEverything extends StatelessWidget {
  const _EraseEverything();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Your data',
            style: text.titleSmall?.copyWith(color: c.text)),
        const SizedBox(height: Space.xs),
        Text(
          'Everything this app knows is on this device. Nothing is sent to a '
          'server of ours, and nothing is kept once you remove it.',
          style: text.bodySmall?.copyWith(color: c.textMuted),
        ),
        const SizedBox(height: Space.md),
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(Radii.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () async {
              if (!await confirmErase(context)) return;
              if (!context.mounted) return;
              await eraseEverything(
                kv: context.read<KvStore>(),
                conversations: context.read<ConversationStore>(),
                artifacts: context.read<ArtifactStore>(),
                notes: context.read<NoteStore>(),
                agents: context.read<AgentStore>(),
                keys: context.read<ApiKeysStore>(),
                turn: context.read<TurnController>(),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Everything has been removed.')),
                );
              }
            },
            child: Container(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.md, vertical: Space.sm),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.md),
                border: Border.all(color: c.danger.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(Icons.delete_forever_outlined,
                      size: 18, color: c.danger),
                  const SizedBox(width: Space.sm),
                  Flexible(
                    child: Text('Delete everything on this device',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium?.copyWith(color: c.danger)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
