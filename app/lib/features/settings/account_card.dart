import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/shift_backend.dart';
import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/account_store.dart';

/// Signing in, and what the account currently buys.
///
/// **Renders nothing when the build has no server behind it**, which is a
/// supported way to run rather than a broken one: the app works signed out on
/// local keys, and that is how the public demo works permanently. Offering a
/// sign-in that cannot succeed would be worse than offering none.
///
/// **Apple and Google lead; email is the alternative underneath.** That order
/// is what most people take, and the pairing is a rule rather than a
/// preference: App Store guideline 4.8 requires an app offering a third-party
/// login to also offer one that limits collection to name and email, which is
/// what Sign in with Apple is. Google alone on iOS is a rejection.
///
/// The two buttons appear only where a redirect can come back — the web today.
/// A desktop or mobile build has no registered deep link yet, so it shows email
/// alone rather than a button that leaves and never returns.
class AccountCard extends StatefulWidget {
  const AccountCard({super.key});

  @override
  State<AccountCard> createState() => _AccountCardState();
}

class _AccountCardState extends State<AccountCard> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<bool> Function() action) async {
    final ok = await action();
    // Cleared only on success. A password wiped after a typo means typing the
    // whole thing again on a phone, which is where this is used.
    if (ok && mounted) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AccountStore>();
    if (!store.isConfigured) return const SizedBox.shrink();

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

          if (store.isSignedIn)
            ..._signedIn(store, c, text)
          else
            ..._signedOut(store, c, text),

          // Both, and they are different things: [problem] is what went wrong,
          // [notice] is what went right but is not finished — "check your
          // email" after a sign-up is not an error, and showing it in red under
          // a form that just worked reads as failure and invites a retry.
          if (store.problem case final problem?) ...[
            const SizedBox(height: Space.sm),
            Text(problem, style: text.bodySmall?.copyWith(color: c.danger)),
          ],
          if (store.notice case final notice?) ...[
            const SizedBox(height: Space.sm),
            Text(notice, style: text.bodySmall?.copyWith(color: c.textMuted)),
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

  List<Widget> _signedOut(AccountStore store, ShiftColors c, TextTheme text) => [
        Text(
          'Sign in to spend a membership instead of your own keys.',
          style: text.bodySmall?.copyWith(color: c.textMuted),
        ),

        // First, and full width, because it is the fast way in and the one
        // most people will take. Email is underneath for anyone who prefers
        // it — not hidden, just second.
        if (store.canSignInWithProvider) ...[
          const SizedBox(height: Space.md),
          for (final provider in OAuthProvider.values) ...[
            SizedBox(
              width: double.infinity,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: kMinTouchTarget),
                child: OutlinedButton.icon(
                  onPressed:
                      store.isBusy ? null : () => store.signInWith(provider),
                  icon: Icon(
                    provider == OAuthProvider.apple
                        ? Icons.apple
                        : Icons.g_mobiledata_rounded,
                    size: 22,
                    color: c.text,
                  ),
                  label: Text('Continue with ${provider.label}',
                      style: text.labelLarge?.copyWith(color: c.text)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.border),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
          ],

          // A rule with a word in it, so what follows reads as the alternative
          // rather than as a second required step.
          Row(
            children: [
              Expanded(child: Divider(color: c.divider)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                child: Text('or',
                    style: text.labelSmall?.copyWith(color: c.textFaint)),
              ),
              Expanded(child: Divider(color: c.divider)),
            ],
          ),
        ],

        const SizedBox(height: Space.md),
        TextField(
          controller: _email,
          enabled: !store.isBusy,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          style: text.bodyMedium?.copyWith(color: c.text),
          cursorColor: c.accent,
          decoration: const InputDecoration(
              isDense: true, labelText: 'Email'),
        ),
        const SizedBox(height: Space.sm),
        TextField(
          controller: _password,
          enabled: !store.isBusy,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          style: text.bodyMedium?.copyWith(color: c.text),
          cursorColor: c.accent,
          decoration:
              const InputDecoration(isDense: true, labelText: 'Password'),
          onSubmitted: (_) => _run(() => store.signIn(
                email: _email.text.trim(),
                password: _password.text,
              )),
        ),
        const SizedBox(height: Space.md),
        Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: TextButton(
                onPressed: store.isBusy
                    ? null
                    : () => _run(() => store.signUp(
                          email: _email.text.trim(),
                          password: _password.text,
                        )),
                child: Text('Create account',
                    style: text.labelLarge?.copyWith(color: c.textMuted)),
              ),
            ),
            const Spacer(),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: FilledButton(
                onPressed: store.isBusy
                    ? null
                    : () => _run(() => store.signIn(
                          email: _email.text.trim(),
                          password: _password.text,
                        )),
                child: const Text('Sign in'),
              ),
            ),
          ],
        ),
      ];
}
