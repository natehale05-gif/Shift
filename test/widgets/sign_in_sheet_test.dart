import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/backend/no_backend.dart';
import 'package:shift_ai/core/theme/app_theme.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/account_store.dart';
import 'package:shift_ai/features/account/sign_in_sheet.dart';
import 'package:shift_ai/features/settings/account_card.dart';

Future<AccountStore> _store() async {
  SharedPreferences.setMockInitialValues({});
  final store = AccountStore(
    backend: NoBackend(),
    persistence: PersistenceService(),
  );
  await store.restore();
  return store;
}

Widget _host(AccountStore store, Widget child) =>
    ChangeNotifierProvider<AccountStore>.value(
      value: store,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );

void main() {
  testWidgets('the sheet asks for an email and a password', (tester) async {
    final store = await _store();
    await tester.pumpWidget(_host(store, const SizedBox()));

    final context = tester.element(find.byType(SizedBox));
    showSignInSheet(context);
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
    store.dispose();
  });

  testWidgets('an empty form is refused before any network call is made',
      (tester) async {
    final store = await _store();
    await tester.pumpWidget(_host(store, const SizedBox()));
    showSignInSheet(tester.element(find.byType(SizedBox)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your email.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
    store.dispose();
  });

  testWidgets('an obviously malformed email is caught before a round trip',
      (tester) async {
    final store = await _store();
    await tester.pumpWidget(_host(store, const SizedBox()));
    showSignInSheet(tester.element(find.byType(SizedBox)));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'not-an-email');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('That does not look like an email address.'),
        findsOneWidget);
    store.dispose();
  });

  testWidgets('switching to create-an-account keeps what was already typed',
      (tester) async {
    // Retyping an email because you tapped the wrong mode first is a small
    // insult the form does not need to deliver.
    final store = await _store();
    await tester.pumpWidget(_host(store, const SizedBox()));
    showSignInSheet(tester.element(find.byType(SizedBox)));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'nate@example.com');
    await tester.tap(find.text('Create an account instead'));
    await tester.pumpAndSettle();

    expect(find.text('Create an account'), findsWidgets);
    expect(find.text('nate@example.com'), findsOneWidget);
    store.dispose();
  });

  testWidgets('a short password is only refused when creating an account',
      (tester) async {
    // Enforcing it at sign-in would lock out an account whose password
    // predates the rule.
    final store = await _store();
    await tester.pumpWidget(_host(store, const SizedBox()));
    showSignInSheet(tester.element(find.byType(SizedBox)));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'nate@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'), 'short');

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters.'), findsNothing);

    await tester.tap(find.text('Create an account instead'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 8 characters.'), findsOneWidget);
    store.dispose();
  });

  testWidgets('the account card renders nothing when no server is configured',
      (tester) async {
    // Every build so far, and the public demo permanently. Offering a sign-in
    // that cannot work would be worse than not mentioning accounts.
    final store = await _store();
    await tester.pumpWidget(_host(store, const AccountCard()));
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    store.dispose();
  });
}
