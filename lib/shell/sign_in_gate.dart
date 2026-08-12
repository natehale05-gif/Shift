import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
import '../data/account_store.dart';
import '../features/settings/sign_in_form.dart';

/// The app is behind an account.
///
/// Signing in used to be optional: the app ran on keys stored on the device and
/// an account only bought a membership. It is now required — the owner's call,
/// and it is the shape a subscription product has, since entitlement is a
/// server fact and there is nothing to attach it to without an identity.
///
/// **Two consequences worth naming rather than discovering.** The public web
/// address is this app, so a visitor now meets a sign-in screen instead of
/// something to try; and someone offline whose stored session has expired
/// cannot get in, because the refresh needs the network. An unexpired stored
/// session opens the app with no request at all, so ordinary offline use is
/// unaffected.
///
/// **A build with no server behind it is not gated.** There would be nothing to
/// sign in to, so the gate would be an app that never opens. That is the same
/// rule every account surface here already follows, and it is what keeps a
/// `--dart-define`-free local build usable.
class SignInGate extends StatefulWidget {
  final Widget child;

  const SignInGate({super.key, required this.child});

  @override
  State<SignInGate> createState() => _SignInGateState();
}

class _SignInGateState extends State<SignInGate> {
  bool _wasSignedIn = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AccountStore>();

    // Swapping what `home` builds does **not** clear anything pushed above it,
    // and Settings — where the Sign out button lives — is a pushed route. So
    // without this, signing out left you looking at Settings with the door
    // underneath: signed out, and still inside the app.
    if (_wasSignedIn && !store.isSignedIn) {
      final navigator = Navigator.maybeOf(context);
      if (navigator != null && navigator.canPop()) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => navigator.popUntil((route) => route.isFirst));
      }
    }
    _wasSignedIn = store.isSignedIn;

    if (!store.isConfigured || store.isSignedIn) return widget.child;

    // `checking` is why this phase exists: a stored session takes a moment to
    // read, and flashing a sign-in screen at somebody who is already signed in
    // reads as having been signed out. Quiet, not a spinner — it is usually
    // one frame, and a spinner that appears for one frame is a flicker.
    if (store.phase == AccountPhase.checking) {
      return Scaffold(backgroundColor: context.colors.ground);
    }
    return const SignInScreen();
  }
}

/// The app's front door.
///
/// The same [SignInForm] Settings shows, given a screen of its own: the app's
/// name above it, one line saying what an account is for, and nothing else to
/// do. There is deliberately no way past — the owner asked for a gate, and a
/// "continue without an account" link is not a gate.
class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.xl),
            child: ConstrainedBox(
              // A credential form does not get wider than it is readable. On a
              // desktop this is a column in the middle of the window rather
              // than two fields stretched across it.
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('SHIFT',
                      style: text.headlineMedium?.copyWith(color: c.text)),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Sign in to continue.',
                    style: text.bodyMedium?.copyWith(color: c.textMuted),
                  ),
                  const SizedBox(height: Space.xl),
                  const SignInForm(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
