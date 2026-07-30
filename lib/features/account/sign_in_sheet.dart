import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tap_targets.dart';
import '../../data/stores/account_store.dart';

/// Signing in, as a sheet rather than a screen.
///
/// It is optional — the app works signed out on keys kept on the device — so
/// it should feel like something you opened, not a gate you were put behind.
/// A sheet dismisses; a screen has to be navigated away from.
Future<void> showSignInSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<AccountStore>(),
      child: const _SignInSheet(),
    ),
  );
}

class _SignInSheet extends StatefulWidget {
  const _SignInSheet();

  @override
  State<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends State<_SignInSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  /// One sheet, two intents. Separate screens for signing in and signing up
  /// mean guessing which one you need before you have typed anything.
  bool _creating = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final store = context.read<AccountStore>();
    final email = _email.text.trim();
    // Never trimmed: a leading or trailing space can be part of a password,
    // and silently removing it makes a correct password fail.
    final password = _password.text;

    final ok = _creating
        ? await store.signUp(email: email, password: password)
        : await store.signIn(email: email, password: password);

    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final store = context.watch<AccountStore>();
    final busy = store.isBusy;

    return Padding(
      // Above the keyboard, which on a phone covers most of this sheet.
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _creating ? 'Create an account' : 'Sign in',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'An account syncs your provider keys across devices and is how '
              'membership works. You can keep using SHIFT AI without one — '
              'keys stay on this device.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _email,
              enabled: !busy,
              autofillHints: const [AutofillHints.email],
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Enter your email.';
                // Deliberately loose. The server is the authority on whether
                // an address exists; this only catches an obvious slip before
                // a round trip.
                if (!text.contains('@') || !text.contains('.')) {
                  return 'That does not look like an email address.';
                }
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _password,
              enabled: !busy,
              obscureText: true,
              autofillHints: [
                _creating ? AutofillHints.newPassword : AutofillHints.password,
              ],
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Password'),
              onFieldSubmitted: (_) => busy ? null : _submit(),
              validator: (value) {
                final text = value ?? '';
                if (text.isEmpty) return 'Enter your password.';
                // Only enforced when creating one. Rejecting a short password
                // at sign-in would lock out an account that legitimately has
                // one from before the rule existed.
                if (_creating && text.length < 8) {
                  return 'Use at least 8 characters.';
                }
                return null;
              },
            ),
            if (store.problem != null) ...[
              const SizedBox(height: AppSpacing.md),
              _Message(
                text: store.problem!,
                icon: Icons.error_outline_rounded,
                color: theme.colorScheme.error,
              ),
            ],
            // A sign-up that needs an emailed confirmation succeeded, so it is
            // said in the ordinary voice rather than in red under a form that
            // did what it was asked.
            if (store.notice != null) ...[
              const SizedBox(height: AppSpacing.md),
              _Message(
                text: store.notice!,
                icon: Icons.mark_email_read_outlined,
                color: colors.textSecondary,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTouchTarget),
              child: FilledButton(
                onPressed: busy ? null : _submit,
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_creating ? 'Create account' : 'Sign in'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                        _creating = !_creating;
                        // The typed email and password carry over — switching
                        // intent should not cost you what you already typed.
                      }),
              child: Text(_creating
                  ? 'I already have an account'
                  : 'Create an account instead'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of feedback under the form — a failure or a notice, which differ
/// only in icon and colour.
class _Message extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color color;

  const _Message({required this.text, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
