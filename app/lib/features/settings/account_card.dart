import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/account_store.dart';
import '../../shell/sign_in_gate.dart';

/// Who is signed in, and what the account currently buys.
///
/// **Signing in is not here.** [SignInGate] stands in front of the whole app,
/// so nobody signed out ever reaches Settings — a form on this card would be a
/// second way in that nothing could ever open. The card is signed-in only, and
/// its one control that changes state is Sign out.
///
/// **Renders nothing when the build has no server behind it.** That build is
/// not gated, so it is the one case where a signed-out person can be looking
/// at this — and there is nothing to sign in to, so there is nothing to show.
class AccountCard extends StatefulWidget {
  const AccountCard({super.key});

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  @override
  Widget build(BuildContext context) {
    final store = context.watch<AccountStore>();

    // Signed out means either a build with no host, or the one frame between
    // Sign out and the gate taking the screen back. Neither wants a card
    // describing an account that is not there.
    if (!store.isConfigured || !store.isSignedIn) return const SizedBox.shrink();

    final c = context.colors;
    final text = Theme.of(context).textTheme;

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
          Text('Account', style: text.titleMedium?.copyWith(color: c.text)),
          const SizedBox(height: Space.xxs),

          ..._signedIn(store, c, text),

          // Signed in, the only failure this card can report is a sign-out or
          // a refresh that did not work.
          if (store.problem case final problem?) ...[
            const SizedBox(height: Space.sm),
            Text(problem, style: text.bodySmall?.copyWith(color: c.danger)),
          ],
        ],
      ),
    );
  }

  List<Widget> _signedIn(AccountStore store, ShiftColors c, TextTheme text) {
    final membership = store.membership;
    return [
      Text(
        store.account?.email ?? 'Signed in',
        style: text.bodyMedium?.copyWith(color: c.textMuted),
      ),
      const SizedBox(height: Space.sm),

      // The plan and the meter together. Either alone misleads: spend with no
      // ceiling looks unbounded, a ceiling with no spend looks unused.
      Text(
        membership.isActive
            ? '${membership.plan ?? 'Plan'} · '
                '\$${(membership.spentMicros / 1000000).toStringAsFixed(2)} of '
                '\$${(membership.ceilingMicros / 1000000).toStringAsFixed(2)} used'
            : 'No plan. Turns use the keys on this device.',
        style: text.bodySmall?.copyWith(color: c.textMuted),
      ),

      const SizedBox(height: Space.md),
      Row(
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTouchTarget),
            child: TextButton(
              onPressed: store.isBusy ? null : store.signOut,
              child: Text('Sign out',
                  style: text.labelLarge?.copyWith(color: c.textMuted)),
            ),
          ),
          const Spacer(),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTouchTarget),
            child: TextButton(
              onPressed: store.isBusy ? null : store.refresh,
              child: Text('Refresh',
                  style: text.labelLarge?.copyWith(color: c.accent)),
            ),
          ),
        ],
      ),
    ];
  }
}
