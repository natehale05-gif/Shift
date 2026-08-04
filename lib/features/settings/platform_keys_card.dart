import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tap_targets.dart';
import '../../data/stores/account_store.dart';
import '../../providers/clients/provider_registry.dart';

/// Where SHIFT's own provider keys are added — the ones a membership buys.
///
/// Shown only to a signed-in admin, and "admin" is a column on the server that
/// no client can write. Hiding this card is therefore presentation, not
/// security: the endpoint refuses a non-admin regardless, so someone who found
/// the request would still get a 403.
///
/// A card in Settings rather than a script or a dashboard row because the
/// person adding these keys is doing it from a phone, and because the vault's
/// encrypting endpoint is the only way in — a dashboard paste would store
/// plaintext.
class PlatformKeysCard extends StatefulWidget {
  const PlatformKeysCard({super.key});

  @override
  State<PlatformKeysCard> createState() => _PlatformKeysCardState();
}

class _PlatformKeysCardState extends State<PlatformKeysCard> {
  final _secret = TextEditingController();
  String _provider = 'anthropic';
  bool _saving = false;
  String? _problem;
  String? _saved;

  @override
  void dispose() {
    _secret.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final secret = _secret.text.trim();
    if (secret.isEmpty || _saving) return;

    setState(() {
      _saving = true;
      _problem = null;
      _saved = null;
    });

    final error = await context
        .read<AccountStore>()
        .putPlatformKey(provider: _provider, secret: secret);

    if (!mounted) return;
    setState(() {
      _saving = false;
      _problem = error;
      if (error == null) {
        _saved = _provider;
        // Cleared on success and only on success. Leaving a key in a text
        // field is how it ends up in a screenshot; clearing it after a failure
        // would mean pasting it again.
        _secret.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AccountStore>();
    if (!store.isConfigured || !store.isSignedIn || !store.isAdmin) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    // The whole vault, not just the spendable part: this is the card that
    // manages SHIFT's keys, and a key that is stored but not yet forwardable
    // is exactly the thing an admin needs to see rather than have hidden.
    final included = store.storedPlatformProviders;

    return Card(
      // The gap belongs to the card rather than to the screen: the screen puts
      // this line in unconditionally, and a SizedBox after it would leave a
      // double gap for the majority who never see the card.
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Included with membership', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Keys SHIFT provides, which members on a plan spend instead of '
              'their own. Encrypted on the way in — nobody, including you, can '
              'read one back out.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
            if (included.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final provider in included)
                    Chip(
                      label: Text(providerLabel(provider)),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _provider,
              decoration: const InputDecoration(labelText: 'Provider'),
              items: [
                for (final provider in _addableProviders)
                  DropdownMenuItem(
                    value: provider,
                    child: Text(providerLabel(provider)),
                  ),
              ],
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _provider = value ?? _provider),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _secret,
              enabled: !_saving,
              obscureText: true,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'API key',
                hintText: 'Paste it here',
              ),
              onSubmitted: (_) => _save(),
            ),
            if (_problem != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _problem!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],
            if (_saved != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                '${providerLabel(_saved!)} saved. Members on a plan can use it '
                'now.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: kMinTouchTarget),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save key'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The providers the vault accepts, matching the edge function's own list.
/// A provider the server does not know is refused there, so keeping these in
/// step is the difference between a clear form and a confusing 400.
const List<String> _addableProviders = [
  'anthropic',
  'openai',
  'gemini',
  'groq',
  'mistral',
  'openrouter',
  'flux',
  'heygen',
  'elevenlabs',
];

/// A provider's display name, from the registry the rest of the app uses, so
/// this card cannot drift into calling things by different names. An id the
/// registry does not know shows as itself rather than as nothing.
String providerLabel(String id) =>
    ProviderRegistry.defaults().byId(id)?.displayName ?? id;
