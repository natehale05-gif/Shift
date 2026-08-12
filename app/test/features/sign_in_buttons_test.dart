import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/backend/shift_backend.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/core/platform/browser_nav.dart';
import 'package:shift/data/account_store.dart';
import 'package:shift/features/settings/sign_in_form.dart';

/// Which sign-in buttons the form offers, and why each one is absent when it is.
///
/// The rule has two independent halves and both produced a real failure:
/// off-web a redirect never comes back, and a provider the host has not enabled
/// answers with raw JSON on a domain the user has never heard of. So a button
/// appears only when the platform can return *and* the host says that provider
/// is configured.
///
/// The third case is the one that decides the design: when the host cannot be
/// asked, **both buttons appear**. Hiding a working sign-in because one request
/// failed is worse than the rare bad redirect — one is a feature that vanished,
/// the other is a page with a Back button.
void main() {
  setUp(() {
    // The platform half is a compile-time constant, false on the VM. Every
    // test here is about the *web* build, so it is pinned rather than left to
    // the host that happens to be running the suite.
    AccountStore.canReturnHere = () => true;
  });

  tearDown(() => AccountStore.canReturnHere = () => canRedirect);

  Future<AccountStore> pump(WidgetTester t, ShiftBackend backend) async {
    final store = AccountStore(backend: backend);
    // `start`, not `restore`: asking the host which providers it has is part
    // of the boot sequence, and a test that skipped it would be asserting the
    // state before the answer arrived rather than the answer.
    await store.start(Uri.parse('https://app.test/'));
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: MaterialApp(
          theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
          home: const Scaffold(body: SingleChildScrollView(child: SignInForm())),
        ),
      ),
    );
    await t.pumpAndSettle();
    return store;
  }

  testWidgets('the host says both, so both are offered', (t) async {
    await pump(t, _Host({OAuthProvider.apple, OAuthProvider.google}));

    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('or'), findsOneWidget, reason: 'email is still underneath');
  });

  testWidgets('the host says only Google, so Apple is not offered', (t) async {
    // The button that was there before this was asked would have sent someone
    // to `Unsupported provider: provider is not enabled`.
    await pump(t, _Host({OAuthProvider.google}));

    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);
  });

  testWidgets('the host says neither, so it is email alone', (t) async {
    await pump(t, _Host(const {}));

    expect(find.textContaining('Continue with'), findsNothing);
    expect(find.text('or'), findsNothing,
        reason: 'a divider between nothing and the form is just a line');
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('the host could not be asked, so nothing is hidden', (t) async {
    // The deliberate direction: unknown is available. Asserted directly
    // because the alternative — a failed request silently removing sign-in —
    // is invisible until someone reports that the buttons went away.
    await pump(t, _Host(const {}, failed: true));

    expect(find.text('Continue with Apple'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('off-web there is nothing to come back to, so neither is offered',
      (t) async {
    AccountStore.canReturnHere = () => false;
    await pump(t, _Host(OAuthProvider.values.toSet()));

    expect(find.textContaining('Continue with'), findsNothing);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('tapping one asks for that provider', (t) async {
    final host = _Host({OAuthProvider.apple, OAuthProvider.google});
    Uri? went;
    AccountStore.returnUrl = () => Uri.parse('https://app.test/');
    await pump(t, host);

    // The store redirects the whole page, which a test cannot follow — so what
    // is checked is the URL it asked the backend for, which is the part this
    // app decides.
    host.onUrl = (url) => went = url;
    await t.tap(find.text('Continue with Apple'));
    await t.pump();

    expect(went!.queryParameters['provider'], 'apple');
  });

  testWidgets('every button clears the tap minimum', (t) async {
    await pump(t, _Host(OAuthProvider.values.toSet()));

    for (final label in ['Continue with Apple', 'Continue with Google']) {
      expect(
        t.getSize(find.widgetWithText(OutlinedButton, label)).height,
        greaterThanOrEqualTo(kMinTouchTarget),
        reason: label,
      );
    }
  });
}

/// A configured backend whose answer about enabled providers the test sets.
///
/// [failed] **throws** rather than returning the everything-set the real
/// implementations return when they cannot find out. That is deliberate: it
/// makes the boot path's own guard the thing under test, and a fake that
/// pre-applied the rule would only be restating it.
class _Host implements ShiftBackend {
  final Set<OAuthProvider> enabled;
  final bool failed;

  /// Records the URL a tap asked for, since the redirect itself leaves.
  void Function(Uri)? onUrl;

  _Host(this.enabled, {this.failed = false});

  @override
  bool get isConfigured => true;

  @override
  Future<Set<OAuthProvider>> enabledProviders() async {
    if (failed) throw StateError('the host could not be asked');
    return enabled;
  }

  @override
  Uri? oauthUrl(OAuthProvider provider, {required Uri redirectTo}) {
    final url = Uri.parse('https://host.test/authorize')
        .replace(queryParameters: {'provider': provider.id});
    onUrl?.call(url);
    return url;
  }

  @override
  ShiftSession? get session => null;

  @override
  Stream<ShiftSession?> get sessionChanges => const Stream.empty();

  @override
  Future<ShiftSession?> restore() async => null;

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
  void dispose() {}

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
