import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/backend/no_backend.dart';
import 'package:shift/backend/shift_backend.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/core/platform/browser_nav.dart';
import 'package:shift/data/account_store.dart';
import 'package:shift/shell/sign_in_gate.dart';

/// Nothing without an account.
///
/// The rule is one line in `app.dart`, which is exactly why it is worth
/// pinning: a gate that lets the app through by accident does not look broken,
/// it looks like the app. So each way past it is asserted separately —
/// signed in, still checking, signed out, and a build with no host.
void main() {
  setUp(() => AccountStore.canReturnHere = () => true);
  tearDown(() => AccountStore.canReturnHere = () => canRedirect);

  const behind = Text('the app', key: Key('behind'));
  final theApp = find.byKey(const Key('behind'));

  Widget host(AccountStore store) => ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
          home: const SignInGate(child: behind),
        ),
      );

  testWidgets('a signed-out visitor gets the door, not the app', (t) async {
    final store = AccountStore(backend: _Host());
    await store.start(Uri.parse('https://app.test/'));
    await t.pumpWidget(host(store));
    await t.pumpAndSettle();

    expect(theApp, findsNothing);
    expect(find.text('Sign in to continue.'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('there is no way past it', (t) async {
    // A gate with a "continue without an account" link is not a gate, and the
    // owner asked for a gate. Asserted as an absence because that is the only
    // way a link nobody added stays not added.
    final store = AccountStore(backend: _Host());
    await store.start(Uri.parse('https://app.test/'));
    await t.pumpWidget(host(store));
    await t.pumpAndSettle();

    for (final out in ['Skip', 'Continue without', 'Maybe later', 'Not now']) {
      expect(find.textContaining(out), findsNothing, reason: out);
    }
  });

  testWidgets('a signed-in person gets the app', (t) async {
    final store = AccountStore(backend: _Host(signedIn: true));
    await store.start(Uri.parse('https://app.test/'));
    await t.pumpWidget(host(store));
    await t.pumpAndSettle();

    expect(theApp, findsOneWidget);
    expect(find.text('Sign in to continue.'), findsNothing);
  });

  testWidgets('while it is still looking, it shows neither', (t) async {
    // The phase exists for this: a stored session takes a moment to read, and
    // flashing the sign-in screen at somebody who is already signed in reads
    // as having been signed out. Asserted with a restore that does not finish.
    final gate = Completer<ShiftSession?>();
    final store = AccountStore(backend: _Host(restoring: gate.future));
    unawaited(store.start(Uri.parse('https://app.test/')));
    await t.pumpWidget(host(store));
    await t.pump();

    expect(store.phase, AccountPhase.checking);
    expect(theApp, findsNothing);
    expect(find.text('Sign in to continue.'), findsNothing);

    gate.complete(null);
    await t.pumpAndSettle();
    expect(find.text('Sign in to continue.'), findsOneWidget);
  });

  testWidgets('a build with no host is not gated', (t) async {
    // There would be nothing to sign in to, so a gate here is an app that
    // never opens rather than an app that is protected.
    final store = AccountStore(backend: NoBackend())..restore();
    await t.pumpWidget(host(store));
    await t.pumpAndSettle();

    expect(theApp, findsOneWidget);
  });

  testWidgets('signing out puts the door back', (t) async {
    final backend = _Host(signedIn: true);
    final store = AccountStore(backend: backend);
    await store.start(Uri.parse('https://app.test/'));
    await t.pumpWidget(host(store));
    await t.pumpAndSettle();
    expect(theApp, findsOneWidget);

    await store.signOut();
    await t.pumpAndSettle();

    expect(theApp, findsNothing,
        reason: 'the app is not left on screen behind a signed-out account');
    expect(find.text('Sign in to continue.'), findsOneWidget);
  });

  testWidgets('signing out from a pushed screen does not leave it up',
      (t) async {
    // Sign out lives in Settings, and Settings is a pushed route. Swapping
    // what `home` builds does nothing to the stack above it, so without the
    // pop you end up signed out and still looking at the app.
    final store = AccountStore(backend: _Host(signedIn: true));
    await store.start(Uri.parse('https://app.test/'));
    await t.pumpWidget(host(store));
    await t.pumpAndSettle();

    final navigator = t.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Settings')))));
    await t.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await store.signOut();
    await t.pumpAndSettle();

    expect(find.text('Settings'), findsNothing);
    expect(find.text('Sign in to continue.'), findsOneWidget);
  });

  testWidgets('it fits a small phone', (t) async {
    // Sign in and Create account side by side overflowed below ~390pt, which
    // is a phone, which is where this is read. Found by running the suite, not
    // by looking — an overflow is a black-and-yellow stripe in a screenshot
    // and an exception in a test, so this pins the narrow end deliberately.
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final store = AccountStore(backend: _Host(enabled: OAuthProvider.values.toSet()));
    await store.start(Uri.parse('https://app.test/'));
    await t.pumpWidget(host(store));
    await t.pumpAndSettle();

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('every way in clears the tap minimum', (t) async {
    final store = AccountStore(backend: _Host(enabled: OAuthProvider.values.toSet()));
    await store.start(Uri.parse('https://app.test/'));
    await t.pumpWidget(host(store));
    await t.pumpAndSettle();

    // Named with their concrete types: `widgetWithText` matches on runtime
    // type, so the shared `ButtonStyleButton` base finds nothing at all — a
    // check that throws rather than one that passes, but still not a check.
    const buttons = <String, Type>{
      'Continue with Apple': OutlinedButton,
      'Continue with Google': OutlinedButton,
      'Sign in': FilledButton,
      'Create account': TextButton,
    };
    for (final MapEntry(key: label, value: type) in buttons.entries) {
      expect(t.getSize(find.widgetWithText(type, label)).height,
          greaterThanOrEqualTo(kMinTouchTarget),
          reason: label);
    }
  });

  testWidgets('the door offers whatever providers the host has', (t) async {
    // The same form Settings shows, so the two cannot disagree about the way
    // in — which is the reason it is one widget rather than two.
    final store = AccountStore(backend: _Host(enabled: {OAuthProvider.apple}));
    await store.start(Uri.parse('https://app.test/'));
    await t.pumpWidget(host(store));
    await t.pumpAndSettle();

    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });
}

/// A configured host whose sign-in state the test sets.
class _Host implements ShiftBackend {
  final bool signedIn;
  final Set<OAuthProvider> enabled;

  /// A restore that has not answered yet, so the checking phase is observable.
  final Future<ShiftSession?>? restoring;

  _Host({this.signedIn = false, this.enabled = const {}, this.restoring});

  final _sessions = StreamController<ShiftSession?>.broadcast();

  @override
  bool get isConfigured => true;

  @override
  ShiftSession? get session => signedIn
      ? ShiftSession(
          account: const ShiftAccount(id: 'u1', email: 'a@example.com'),
          accessToken: 'token',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        )
      : null;

  @override
  Stream<ShiftSession?> get sessionChanges => _sessions.stream;

  @override
  Future<ShiftSession?> restore() => restoring ?? Future.value(session);

  @override
  Future<void> signOut() async => _sessions.add(null);

  @override
  Future<Set<OAuthProvider>> enabledProviders() async => enabled;

  @override
  Uri? oauthUrl(OAuthProvider provider, {required Uri redirectTo}) =>
      Uri.parse('https://host.test/authorize?provider=${provider.id}');

  @override
  Future<ShiftSession?> adoptCallback(Uri url) async => null;

  @override
  Future<bool> isAdmin() async => false;

  @override
  Future<Membership> membership() async => Membership.none;

  @override
  Future<List<String>> includedProviders() async => const [];

  @override
  Future<List<ProviderKeyInfo>> listProviderKeys() async => const [];

  @override
  List<SetupLink> setupLinks() => const [];

  @override
  void dispose() => _sessions.close();

  // Nothing below is reached. They throw rather than answering plausibly: a
  // surface that quietly started calling one would otherwise pass while doing
  // something this fake never modelled.
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
  Future<ProviderKeyInfo> putProviderKey({
    required String provider,
    required String secret,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteProviderKey(String id) => throw UnimplementedError();

  @override
  Future<void> putPlatformKey({
    required String provider,
    required String secret,
  }) =>
      throw UnimplementedError();

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
    required String path,
    required Map<String, dynamic> body,
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
