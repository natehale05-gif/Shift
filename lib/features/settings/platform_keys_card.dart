import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/account_store.dart';
import '../../providers/proxyable.dart';
import '../../providers/registry.dart';

/// Where SHIFT's own provider keys are added — the ones a membership buys.
///
/// Shown only to a signed-in admin, and "admin" is a column on the server that
/// no client can write. Hiding this card is therefore presentation, not
/// security: the endpoint checks the same column and refuses a non-admin
/// regardless, so someone who found the request would still get a 403.
///
/// **A card in the app rather than a dashboard row or a script**, for a reason
/// that is not convenience: the vault's encrypting endpoint is the only way in,
/// and a key pasted into a database console would be stored in plaintext. It
/// also means the key travels from the clipboard of the person who owns it
/// straight to the server — never through a file, a repository, or a
/// conversation.
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

  /// The vault's chips. [spendable] carries the accent; the rest are drawn in
  /// the muted neutrals, because reading identically is what made an inert key
  /// look like coverage.
  Widget _chips(ShiftColors c, TextTheme text, List<String> providers,
          {required bool spendable}) =>
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final provider in providers)
            Container(
              decoration: BoxDecoration(
                color: spendable ? c.accentWash : c.surfaceSunken,
                borderRadius: BorderRadius.circular(Radii.pill),
                border: spendable ? null : Border.all(color: c.border),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: Space.md, vertical: Space.xs),
              child: Text(providerLabel(provider),
                  style: text.labelMedium
                      ?.copyWith(color: spendable ? c.accent : c.textMuted)),
            ),
        ],
      );

  Future<void> _save() async {
    // Whitespace stripped, not trimmed. A key pasted with a line break in the
    // middle was stored with it and sent as a header, which the provider
    // answered 401 to — and the app then blamed the key, which was the one
    // thing that was fine. Same rule as the personal key field.
    final secret = _secret.text.replaceAll(RegExp(r'\s'), '');
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
        // Cleared on success and only on success. Leaving a key in a field is
        // how it ends up in a screenshot; clearing it after a failure would
        // mean pasting it again.
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

    final c = context.colors;
    final text = Theme.of(context).textTheme;
    // The whole vault, not only the spendable part: this is the card that
    // manages SHIFT's keys, and one that is stored but not yet forwardable is
    // exactly what an admin needs to see rather than have hidden.
    //
    // Split, though, because showing them alike was its own small lie. A
    // screenshot of this card had `heygen` and `elevenlabs` in the same accent
    // pill as Claude and OpenAI, and v2 has no client for either — so those two
    // could never be spent by anything, while reading as covered.
    final stored = store.storedPlatformProviders;
    final spendable =
        stored.where(proxyableProviders.contains).toList(growable: false);
    final inert = stored
        .where((p) => !proxyableProviders.contains(p))
        .toList(growable: false);

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
          Text('Included with membership',
              style: text.titleMedium?.copyWith(color: c.text)),
          const SizedBox(height: Space.xxs),
          Text(
            'Keys SHIFT provides, which members on a plan spend instead of '
            'their own. Encrypted on the way in — nobody, including you, can '
            'read one back out.',
            style: text.bodySmall?.copyWith(color: c.textMuted),
          ),

          if (spendable.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            _chips(c, text, spendable, spendable: true),
          ],
          if (inert.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Text('Stored, not spendable',
                style: text.labelMedium?.copyWith(color: c.text)),
            const SizedBox(height: Space.xxs),
            Text(
              'SHIFT holds a key, but this app has no client for it yet, so '
              'nothing can spend it.',
              style: text.bodySmall?.copyWith(color: c.textMuted),
            ),
            const SizedBox(height: Space.xs),
            _chips(c, text, inert, spendable: false),
          ],

          const SizedBox(height: Space.md),
          DropdownButtonFormField<String>(
            initialValue: _provider,
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Provider',
            ),
            items: [
              for (final provider in _addable)
                DropdownMenuItem(
                  value: provider,
                  child: Text(providerLabel(provider)),
                ),
            ],
            onChanged: _saving
                ? null
                : (value) => setState(() => _provider = value ?? _provider),
          ),

          const SizedBox(height: Space.md),
          TextField(
            controller: _secret,
            enabled: !_saving,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            style: text.bodyMedium?.copyWith(color: c.text),
            cursorColor: c.accent,
            decoration: InputDecoration(
              isDense: true,
              labelText: 'API key',
              hintText: 'Paste it here',
              hintStyle: text.bodyMedium?.copyWith(color: c.textFaint),
            ),
            onSubmitted: (_) => _save(),
          ),

          if (_problem case final problem?) ...[
            const SizedBox(height: Space.sm),
            Text(problem, style: text.bodySmall?.copyWith(color: c.danger)),
          ],
          if (_saved case final provider?) ...[
            const SizedBox(height: Space.sm),
            Text(
              '${providerLabel(provider)} saved. Members on a plan can use it '
              'now.',
              style: text.bodySmall?.copyWith(color: c.success),
            ),
          ],

          const SizedBox(height: Space.md),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
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
    );
  }
}

/// What the vault accepts.
///
/// The proxy's own allowlist, not a third hand-written copy of it —
/// `tool/scan_proxy_providers.py` fails the build if that list and the
/// server's drift. v1 has a separate list here and it is one more place to
/// forget.
///
/// Sorted, because a dropdown whose order comes from a `Set`'s iteration is a
/// dropdown that reorders itself when somebody adds an entry.
final List<String> _addable = proxyableProviders.toList()..sort();
