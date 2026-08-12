import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/backend/no_backend.dart';
import 'package:shift/backend/shift_backend.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/account_store.dart';
import 'package:shift/features/settings/account_card.dart';
import 'package:shift/features/settings/platform_keys_card.dart';
import 'package:shift/providers/proxyable.dart';

/// Where SHIFT's own keys go in — the ones a membership spends.
///
/// The card is admin-only, and that gate is checked here because it is the one
/// thing about it that is easy to get wrong in a way nobody notices: a card
/// that appears for everyone still cannot store a key (the endpoint checks the
/// same column), but it invites people to paste a secret into a form that will
/// refuse it.
void main() {
  Widget host(ShiftBackend backend) {
    // `..restore()` because that is what the composition root does, and it is
    // what asks the server whether this account is an admin. Without it the
    // store is in its `checking` phase forever and the admin card can never
    // appear — a test that skipped it would have been asserting the loading
    // state, not the answer.
    final store = AccountStore(backend: backend)..restore();
    return ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: Column(children: [AccountCard(), PlatformKeysCard()]),
          ),
        ),
      ),
    );
  }

  group('who sees it', () {
    testWidgets('nobody, when the build has no server', (t) async {
      // The default, and the public demo permanently. Neither card is a
      // placeholder to be greyed out — they are simply not part of that app.
      await t.pumpWidget(host(NoBackend()));
      await t.pumpAndSettle();

      expect(find.byType(PlatformKeysCard), findsOneWidget);
      expect(find.text('Included with membership'), findsNothing);
      expect(find.text('Account'), findsNothing);
    });

    testWidgets('not a signed-out visitor to a configured build', (t) async {
      await t.pumpWidget(host(_Configured()));
      await t.pumpAndSettle();

      // Neither card, and the account card is empty rather than offering a
      // sign-in: `SignInGate` stands in front of the whole app, so a signed-out
      // person never reaches Settings and a form here could never be opened.
      expect(find.text('Account'), findsNothing);
      expect(find.text('Sign in'), findsNothing);
      expect(find.text('Included with membership'), findsNothing);
    });

    testWidgets('not a signed-in member who is not an admin', (t) async {
      // The case that matters most: a paying member is signed in, and must not
      // be shown the form that manages the keys they are spending.
      await t.pumpWidget(host(_Configured(signedIn: true)));
      await t.pumpAndSettle();

      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Included with membership'), findsNothing);
    });

    testWidgets('an admin does', (t) async {
      await t.pumpWidget(host(_Configured(signedIn: true, admin: true)));
      await t.pumpAndSettle();

      expect(find.text('Included with membership'), findsOneWidget);
      expect(find.text('Save key'), findsOneWidget);
    });
  });

  group('putting a key in', () {
    Future<_Configured> pumpAdmin(WidgetTester t) async {
      final backend = _Configured(signedIn: true, admin: true);
      await t.pumpWidget(host(backend));
      await t.pumpAndSettle();
      return backend;
    }

    testWidgets('the secret reaches the vault, whitespace and all removed',
        (t) async {
      // A key pasted with a line break in the middle was stored with it and
      // sent as a header, and the 401 that came back read as a bad key. Same
      // defect, same fix, in the second place a key is now typed.
      final backend = await pumpAdmin(t);

      await t.enterText(find.byType(TextField).last, 'sk-ant-abc\n def');
      await t.tap(find.text('Save key'));
      await t.pumpAndSettle();

      expect(backend.stored.single.secret, 'sk-ant-abcdef');
    });

    testWidgets('and the field is cleared afterwards', (t) async {
      // A key left in a text field is a key in the next screenshot.
      await pumpAdmin(t);

      await t.enterText(find.byType(TextField).last, 'sk-ant-real');
      await t.tap(find.text('Save key'));
      await t.pumpAndSettle();

      expect(find.text('sk-ant-real'), findsNothing);
      expect(find.textContaining('saved'), findsOneWidget);
    });

    testWidgets('a failure keeps it, so it is not typed twice', (t) async {
      final backend = await pumpAdmin(t);
      backend.refuse = true;

      await t.enterText(find.byType(TextField).last, 'sk-ant-real');
      await t.tap(find.text('Save key'));
      await t.pumpAndSettle();

      expect(backend.stored, isEmpty);
      expect(find.text('sk-ant-real'), findsOneWidget);
    });

    testWidgets('nothing is sent for an empty field', (t) async {
      final backend = await pumpAdmin(t);
      await t.tap(find.text('Save key'));
      await t.pumpAndSettle();
      expect(backend.stored, isEmpty);
    });
  });

  test('the dropdown offers only what the proxy will forward', () {
    // A provider the server refuses sends a call out with no credential and
    // gets a 401, which reads as a bad key rather than as a routing mistake.
    // The list is the proxy's own, checked against the server by
    // tool/scan_proxy_providers.py.
    expect(proxyableProviders, contains('anthropic'));
    expect(proxyableProviders, isNot(contains('flux')));
  });

  testWidgets('every control clears the tap minimum', (t) async {
    await t.pumpWidget(host(_Configured(signedIn: true, admin: true)));
    await t.pumpAndSettle();

    expect(t.getSize(find.widgetWithText(FilledButton, 'Save key')).height,
        greaterThanOrEqualTo(kMinTouchTarget));
  });
}

/// A backend that is configured, with sign-in state the test controls.
///
/// Not a mock of HTTP: what these tests are about is which surfaces appear for
/// whom, and that decision is made from three booleans this hands over.
class _Configured implements ShiftBackend {
  final bool signedIn;
  final bool admin;

  /// Set to make the next write fail, so "kept on failure" is testable.
  bool refuse = false;

  final List<({String provider, String secret})> stored = [];

  _Configured({this.signedIn = false, this.admin = false});

  @override
  bool get isConfigured => true;

  @override
  ShiftSession? get session => signedIn
      ? ShiftSession(
          account: const ShiftAccount(id: 'u1', email: 'admin@example.com'),
          accessToken: 'token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        )
      : null;

  @override
  Stream<ShiftSession?> get sessionChanges => const Stream.empty();

  @override
  Future<ShiftSession?> restore() async => session;

  /// A plausible URL and no callback. These tests are about the vault, not
  /// about signing in — but the interface is abstract on purpose, so adding a
  /// method here is the compiler insisting every implementation makes a
  /// decision rather than inheriting a default that might be wrong.
  @override
  Uri? oauthUrl(OAuthProvider provider, {required Uri redirectTo}) =>
      Uri.parse('https://host.test/authorize?provider=${provider.id}');

  @override
  Future<ShiftSession?> adoptCallback(Uri url) async => null;

  @override
  Future<Set<OAuthProvider>> enabledProviders() async => const {};

  @override
  Future<bool> isAdmin() async => admin;

  @override
  Future<void> putPlatformKey({
    required String provider,
    required String secret,
  }) async {
    if (refuse) {
      throw const BackendException(
          BackendProblem.unavailable, 'Could not reach the server.');
    }
    stored.add((provider: provider, secret: secret));
  }

  @override
  Future<List<String>> includedProviders() async =>
      [for (final key in stored) key.provider];

  @override
  Future<Membership> membership() async => Membership.none;

  @override
  Future<List<ProviderKeyInfo>> listProviderKeys() async => const [];

  @override
  List<SetupLink> setupLinks() => const [];

  @override
  void dispose() {}

  // Nothing below is reached by these tests. They throw rather than returning
  // a plausible empty value: a surface that quietly started calling one would
  // otherwise pass while doing something this fake never modelled.
  @override
  Future<ShiftSession> signIn({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<ShiftSession> signUp({
    required String email,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<ProviderKeyInfo> putProviderKey({
    required String provider,
    required String secret,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteProviderKey(String id) => throw UnimplementedError();

  @override
  Future<({Uri base, Map<String, String> headers})?> managedProviderCall(
          String provider) =>
      throw UnimplementedError();

  @override
  Future<void> grantMembership({
    String? email,
    String status = 'active',
    String plan = 'granted',
    required int ceilingMicros,
  }) =>
      throw UnimplementedError();

  @override
  Future<({int status, String body})?> probeProxy(
    String provider, {
    Map<String, String> extraHeaders = const {},
  }) =>
      throw UnimplementedError();

  @override
  Future<Uri> billingPortal({String? plan}) => throw UnimplementedError();

  @override
  Future<List<ScheduledTask>> listScheduledTasks() =>
      throw UnimplementedError();

  @override
  Future<ScheduledTask> saveScheduledTask(ScheduledTask task) =>
      throw UnimplementedError();

  @override
  Future<void> deleteScheduledTask(String id) => throw UnimplementedError();
}
