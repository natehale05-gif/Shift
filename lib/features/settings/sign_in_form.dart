import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../backend/shift_backend.dart';
import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../data/account_store.dart';

/// Signing in: the providers, then email.
///
/// One implementation, two places — the app's front door and the Account card
/// in Settings. Two copies of a credential form is the redundancy this project
/// spent a wave removing from Settings, and it is worse here: the copies would
/// drift on which providers they offer, and the one people meet first is the
/// one nobody is looking at.
///
/// **Apple and Google lead; email is the alternative underneath.** That order
/// is what most people take, and the pairing is a rule rather than a
/// preference: App Store guideline 4.8 requires an app offering a third-party
/// login to also offer one that limits collection to name and email, which is
/// what Sign in with Apple is. Google alone on iOS is a rejection.
///
/// A provider's button appears only when both halves are true: this platform
/// can complete a redirect, and the host has that provider configured. Either
/// one missing produced a real failure — off-web the person never comes back,
/// and an unconfigured provider answers with raw JSON on the host's own domain
/// and no way forward. Neither is worth a button.
class SignInForm extends StatefulWidget {
  const SignInForm({super.key});

  @override
  State<SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<SignInForm> {
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
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // First, and full width, because it is the fast way in and the one
        // most people will take. Email is underneath for anyone who prefers
        // it — not hidden, just second.
        if (store.signInProviders.isNotEmpty) ...[
          for (final provider in store.signInProviders) ...[
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
                child:
                    Text('or', style: text.labelSmall?.copyWith(color: c.textFaint)),
              ),
              Expanded(child: Divider(color: c.divider)),
            ],
          ),
          const SizedBox(height: Space.md),
        ],

        TextField(
          controller: _email,
          enabled: !store.isBusy,
          autocorrect: false,
          keyboardType: TextInputType.emailAddress,
          style: text.bodyMedium?.copyWith(color: c.text),
          cursorColor: c.accent,
          decoration: const InputDecoration(isDense: true, labelText: 'Email'),
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

        // Stacked, not a row with a Spacer between them. Side by side, the two
        // labels overflow below about 390pt — which is a phone, and a phone is
        // where this is used. Full width also puts Sign in at the same weight
        // as the provider buttons above it, so the column reads as one set of
        // ways in rather than a form with a small button at the end.
        SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
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
        ),
        const SizedBox(height: Space.xs),
        SizedBox(
          width: double.infinity,
          child: ConstrainedBox(
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
        ),

        // Both, and they are different things: [problem] is what went wrong,
        // [notice] is what went right but is not finished — "check your email"
        // after a sign-up is not an error, and showing it in red under a form
        // that just worked reads as failure and invites a retry.
        if (store.problem case final problem?) ...[
          const SizedBox(height: Space.sm),
          Text(problem, style: text.bodySmall?.copyWith(color: c.danger)),
        ],
        if (store.notice case final notice?) ...[
          const SizedBox(height: Space.sm),
          Text(notice, style: text.bodySmall?.copyWith(color: c.textMuted)),
        ],
      ],
    );
  }
}
