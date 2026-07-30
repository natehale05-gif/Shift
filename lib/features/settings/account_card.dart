import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../data/stores/account_store.dart';
import '../account/sign_in_sheet.dart';

/// The account surface in Settings: sign in, see the membership, sign out.
///
/// Renders nothing at all when no server is configured. That is not a
/// degraded state — it is what every build has been so far and what the public
/// demo stays. Offering a sign-in that cannot work would be worse than not
/// mentioning accounts.
class AccountCard extends StatelessWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AccountStore>();
    if (!store.isConfigured) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            switch (store.phase) {
              // Not "signed out" — we have not looked yet. Saying the wrong
              // one for half a second is how an app tells you you are logged
              // out every time it launches.
              AccountPhase.checking => Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Checking…',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.textSecondary)),
                  ],
                ),
              AccountPhase.signedIn => _SignedIn(store: store),
              _ => _SignedOut(store: store),
            },
          ],
        ),
      ),
    );
  }
}

class _SignedOut extends StatelessWidget {
  final AccountStore store;
  const _SignedOut({required this.store});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sign in to keep your provider keys on the server instead of this '
          'device, and to use a membership. Everything works without one.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.md),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: () => showSignInSheet(context),
            child: const Text('Sign in'),
          ),
        ),
      ],
    );
  }
}

class _SignedIn extends StatelessWidget {
  final AccountStore store;
  const _SignedIn({required this.store});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final membership = store.membership;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                store.account?.email ?? 'Signed in',
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: store.signOut,
              child: const Text('Sign out'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          membership.isActive
              ? '${membership.plan ?? 'Member'} · '
                  '${_dollars(membership.spentMicros)} of '
                  '${_dollars(membership.ceilingMicros)} used this month'
              : 'No membership — SHIFT AI uses the keys you add.',
          style:
              theme.textTheme.bodySmall?.copyWith(color: colors.textSecondary),
        ),
        if (membership.isActive) ...[
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: LinearProgressIndicator(
              value: membership.fractionUsed,
              minHeight: 6,
              backgroundColor: colors.surfaceAlt,
            ),
          ),
        ],
        if (store.serverKeys.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            'Keys on the server',
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final key in store.serverKeys)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                // The last four is all the server will ever tell a client
                // about a stored key, which is the point of storing it there.
                '${key.provider} · ····${key.lastFour}'
                '${key.managed ? ' · included' : ''}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.textSecondary),
              ),
            ),
        ],
      ],
    );
  }

  /// Micros are millionths of a dollar; people read dollars.
  static String _dollars(int micros) =>
      '\$${(micros / 1000000).toStringAsFixed(2)}';
}
