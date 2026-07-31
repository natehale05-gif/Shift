import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../backend/setup_probe.dart';
import '../../backend/shift_backend.dart';
import '../../core/platform/open_url.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tap_targets.dart';
import '../../data/stores/account_store.dart';

/// Everything still standing between a signed-in admin and a working server,
/// with a button for each thing that can be done from here.
///
/// It exists because the list it replaces was a chat message: grant yourself a
/// membership in a SQL editor, change a Site URL four taps into a dashboard,
/// add two GitHub settings in two different tabs, then send a message and
/// describe what you saw. Every one of those is worse on a phone, and the last
/// one is not even answerable — from inside a chat, "not deployed", "not
/// entitled" and "the key is wrong" all look like a reply that never came.
///
/// So: the two things the server can do, it does. The two it cannot are one
/// tap and a pre-filled clipboard. And the state is *probed*, never assumed —
/// a checklist that only records what you told it is a checklist that lies.
class SetupCard extends StatefulWidget {
  const SetupCard({super.key});

  @override
  State<SetupCard> createState() => _SetupCardState();
}

class _SetupCardState extends State<SetupCard> {
  ProxyProbeResult? _probe;
  bool _testing = false;
  bool _granting = false;
  String? _grantProblem;

  /// Dollars, because that is what a person types. Converted at the boundary.
  final _ceiling = TextEditingController(text: '25');

  @override
  void dispose() {
    _ceiling.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _probe = null;
    });
    final result = await context.read<AccountStore>().testProxy();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _probe = result;
    });
  }

  Future<void> _grant() async {
    final dollars = double.tryParse(_ceiling.text.trim());
    if (dollars == null || dollars < 0) {
      setState(() => _grantProblem = 'Enter an amount in dollars.');
      return;
    }

    setState(() {
      _granting = true;
      _grantProblem = null;
    });
    final error = await context.read<AccountStore>().grantMembership(
          plan: 'founder',
          ceilingMicros: (dollars * 1000000).round(),
        );
    if (!mounted) return;
    setState(() {
      _granting = false;
      _grantProblem = error;
    });
  }

  Future<void> _copy(String value, String label) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AccountStore>();
    if (!store.isConfigured || !store.isSignedIn || !store.isAdmin) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final membership = store.membership;
    final covered = store.includedProviders;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Server setup', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'What is working, and what is left. Everything here is checked '
              'against the server, not remembered.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.md),

            _StatusRow(
              done: true,
              label: 'Signed in',
              detail: store.account?.email ?? '',
            ),
            _StatusRow(
              done: membership.canSpendManaged,
              label: 'Membership',
              detail: membership.canSpendManaged
                  ? '\$${_dollars(membership.spentMicros)} of '
                      '\$${_dollars(membership.ceilingMicros)} used'
                  : 'No plan that can spend yet',
            ),
            _StatusRow(
              done: covered.isNotEmpty,
              label: 'Providers covered',
              detail: covered.isEmpty ? 'None added yet' : covered.join(', '),
            ),
            _StatusRow(
              done: _probe?.isWorking ?? false,
              unknown: _probe == null,
              label: 'Server proxy',
              detail: _probe?.message ?? 'Not tested yet',
            ),

            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),

            // ---- the one button that answers the question we cannot ------
            Text('Test the connection', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Sends one tiny request through the server and says exactly what '
              'came back.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: FilledButton.icon(
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('Run test'),
              ),
            ),
            if (_probe?.detail != null) ...[
              const SizedBox(height: AppSpacing.sm),
              // The server's own words, kept out of the headline sentence but
              // available — it is usually the thing that identifies the fault.
              SelectableText(
                _probe!.detail!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),

            // ---- entitlement, which used to be SQL -----------------------
            Text('Give this account a plan', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Until payments are set up, a plan is granted rather than bought. '
              'The amount is the most it may spend of SHIFT\'s keys per month.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _ceiling,
                    enabled: !_granting,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Monthly cap',
                      prefixText: '\$',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: kMinTouchTarget),
                  child: FilledButton.tonal(
                    onPressed: _granting ? null : _grant,
                    child: _granting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Grant'),
                  ),
                ),
              ],
            ),
            if (_grantProblem != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                _grantProblem!,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],

            const SizedBox(height: AppSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.md),

            // ---- the two that only a dashboard can do --------------------
            Text('Two things only a dashboard can do',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Each opens the exact page and copies what to paste, so nothing '
              'has to be typed.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.sm),

            // Rendered, not authored. Every URL and value here names the
            // host, which is the backend's business — the boundary scan
            // caught the first version of this file doing it itself.
            for (final link in store.setupLinks)
              _LinkRow(link: link, onCopy: _copy),
          ],
        ),
      ),
    );
  }
}

String _dollars(int micros) => (micros / 1000000).toStringAsFixed(2);

/// One line of live state.
///
/// [unknown] is its own look rather than a failure, because "not tested yet"
/// and "tested and broken" are different things and showing a red cross for
/// the first would send someone fixing what was never checked.
class _StatusRow extends StatelessWidget {
  final bool done;
  final bool unknown;
  final String label;
  final String detail;

  const _StatusRow({
    required this.done,
    required this.label,
    required this.detail,
    this.unknown = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    final (icon, colour) = unknown
        ? (Icons.remove_circle_outline_rounded, colors.textSecondary)
        : done
            // The theme has no 'success' colour, and inventing one here
            // would be a sixth green nobody chose. The primary accent is
            // what this design system already uses to mean "this is on".
            ? (Icons.check_circle_rounded, theme.colorScheme.primary)
            : (Icons.radio_button_unchecked_rounded, colors.textSecondary);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colour),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                if (detail.isNotEmpty)
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A thing to go and do elsewhere: open the page, and take the value with you.
class _LinkRow extends StatelessWidget {
  final SetupLink link;
  final Future<void> Function(String value, String label) onCopy;

  const _LinkRow({required this.link, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(link.title,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinTouchTarget),
                child: OutlinedButton.icon(
                  onPressed: () => openUrl(link.url.toString()),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(link.action),
                ),
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinTouchTarget),
                child: TextButton.icon(
                  onPressed: () => onCopy(link.copyValue, link.copyLabel),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: Text('Copy ${link.copyLabel}'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
