import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shift/backend/no_backend.dart';
import 'package:shift/backend/shift_backend.dart';
import 'package:shift/core/design/metrics.dart';
import 'package:shift/core/design/theme.dart';
import 'package:shift/data/account_store.dart';
import 'package:shift/features/settings/server_card.dart';
import 'package:shift/providers/proxy_routes.dart';

/// The surface that gives two waves of proxy diagnostics a caller.
///
/// `testProxy` and `readProxyResponse` were written, tested, and reached from
/// nowhere in v2 — so the controls built to tell "not deployed" from "not
/// entitled" from "the key is wrong" did not exist in the app being used, and
/// the loop stayed *"send a turn and describe what you saw"*.
void main() {
  Widget host(ShiftBackend backend) {
    final store = AccountStore(backend: backend)..restore();
    return ChangeNotifierProvider.value(
      value: store,
      child: MaterialApp(
        theme: shiftTheme(Brightness.light, TargetPlatform.iOS),
        home: const Scaffold(
          body: SingleChildScrollView(child: ServerCard()),
        ),
      ),
    );
  }

  group('who sees it', () {
    testWidgets('nobody, when the build has no server', (t) async {
      await t.pumpWidget(host(NoBackend()));
      await t.pumpAndSettle();
      expect(find.text('Server'), findsNothing);
    });

    testWidgets('not a signed-out visitor', (t) async {
      await t.pumpWidget(host(_Host()));
      await t.pumpAndSettle();
      expect(find.text('Server'), findsNothing);
    });

    testWidgets('a signed-in account does', (t) async {
      await t.pumpWidget(host(_Host(signedIn: true)));
      await t.pumpAndSettle();
      expect(find.text('Server'), findsOneWidget);
      expect(find.text('Server routes'), findsOneWidget);
    });
  });

  group('the routes row', () {
    testWidgets('names the route a stale server will not forward', (t) async {
      // The deployed proxy on the day this was written: no image route, five
      // commits behind, refusing every picture a plan paid for.
      final backend = _Host(signedIn: true, routes: _olderServer);
      await t.pumpWidget(host(backend));
      await t.pumpAndSettle();

      await t.tap(find.text('Check'));
      await t.pumpAndSettle();

      expect(find.textContaining('POST /v1/images/generations'), findsWidgets);
      expect(find.textContaining('older build'), findsOneWidget);
    });

    testWidgets('every missing route is listed, not just counted', (t) async {
      // With one missing route the sentence names it, so the list underneath
      // could be absent and the previous test would still pass — it did, when
      // the list was removed on purpose. With two, the sentence says "2 of the
      // routes" and only the list can name them.
      final backend = _Host(signedIn: true, routes: _serverMissingTwo);
      await t.pumpWidget(host(backend));
      await t.pumpAndSettle();

      await t.tap(find.text('Check'));
      await t.pumpAndSettle();

      expect(find.textContaining('2 of the routes'), findsOneWidget);
      expect(find.text('openai POST /v1/images/generations'), findsOneWidget);
      expect(find.text('anthropic POST /v1/messages'), findsOneWidget);
    });

    testWidgets('a server that predates the check is placed, not blamed',
        (t) async {
      final backend = _Host(signedIn: true, routes: (status: 404, body: ''));
      await t.pumpWidget(host(backend));
      await t.pumpAndSettle();

      await t.tap(find.text('Check'));
      await t.pumpAndSettle();

      expect(find.textContaining('older than the app'), findsOneWidget);
    });

    testWidgets('a current server says so and lists nothing', (t) async {
      final backend = _Host(signedIn: true, routes: _currentServer);
      await t.pumpWidget(host(backend));
      await t.pumpAndSettle();

      await t.tap(find.text('Check'));
      await t.pumpAndSettle();

      expect(find.textContaining('forwards everything'), findsOneWidget);
      expect(find.textContaining('POST /v1/'), findsNothing);
    });

    testWidgets('it is not asked until it is asked', (t) async {
      // A check that ran on build would spend a round trip every time Settings
      // opened, for an answer that changes on a deploy.
      final backend = _Host(signedIn: true, routes: _currentServer);
      await t.pumpWidget(host(backend));
      await t.pumpAndSettle();

      expect(backend.routeChecks, 0);
    });
  });

  group('test connection', () {
    testWidgets('is offered per covered provider, and only those', (t) async {
      final backend = _Host(signedIn: true, covered: ['anthropic', 'openai']);
      await t.pumpWidget(host(backend));
      await t.pumpAndSettle();

      // Scoped to the button: the covered-providers row names them too, and a
      // bare text match would pass whether or not a control exists.
      expect(find.widgetWithText(TextButton, 'anthropic'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'openai'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'gemini'), findsNothing);
    });

    testWidgets('reports what came back, in a sentence', (t) async {
      final backend = _Host(
        signedIn: true,
        covered: ['openai'],
        probe: (
          status: 403,
          body: '{"message":"That endpoint is not available through SHIFT."}',
        ),
      );
      await t.pumpWidget(host(backend));
      await t.pumpAndSettle();

      await t.tap(find.widgetWithText(TextButton, 'openai'));
      await t.pumpAndSettle();

      // The server's own words, not advice about a key the member does not
      // hold — which is what the chat card said for two weeks.
      expect(find.text('That endpoint is not available through SHIFT.'),
          findsOneWidget);
      expect(find.textContaining('key was rejected'), findsNothing);
    });

    testWidgets('sends the path that provider actually uses', (t) async {
      // `probeProxy` used to send Claude's `/v1/messages` at whoever was
      // named, so for five of six the allowlist refused it and the one control
      // built to tell these states apart answered 403 for a healthy provider.
      final backend = _Host(signedIn: true, covered: ['openai']);
      await t.pumpWidget(host(backend));
      await t.pumpAndSettle();

      await t.tap(find.widgetWithText(TextButton, 'openai'));
      await t.pumpAndSettle();

      expect(backend.probedPaths, ['/v1/chat/completions']);
    });
  });

  testWidgets('every control clears the tap minimum', (t) async {
    final backend = _Host(signedIn: true, covered: ['anthropic', 'openai']);
    await t.pumpWidget(host(backend));
    await t.pumpAndSettle();

    for (final label in ['Check', 'anthropic', 'openai']) {
      expect(t.getSize(find.widgetWithText(TextButton, label)).height,
          greaterThanOrEqualTo(kMinTouchTarget),
          reason: label);
    }
  });
}

/// The live proxy on 3 August: everything but pictures.
final _olderServer = (
  status: 200,
  body: jsonEncode({
    'version': 'deadbeef',
    'allow': {
      for (final MapEntry(key: id, value: routes) in requiredProxyRoutes.entries)
        id: [
          for (final route in routes)
            if (route != 'POST /v1/images/generations') route,
        ],
    },
  }),
);

/// Two routes short, so the list is the only thing that can name them.
final _serverMissingTwo = (
  status: 200,
  body: jsonEncode({
    'version': 'deadbeef',
    'allow': {
      for (final MapEntry(key: id, value: routes) in requiredProxyRoutes.entries)
        id: [
          for (final route in routes)
            if (route != 'POST /v1/images/generations' &&
                route != 'POST /v1/messages')
              route,
        ],
    },
  }),
);

final _currentServer = (
  status: 200,
  body: jsonEncode({'version': 'cafebabe', 'allow': requiredProxyRoutes}),
);

class _Host implements ShiftBackend {
  final bool signedIn;
  final List<String> covered;
  final ({int status, String body})? routes;
  final ({int status, String body})? probe;

  int routeChecks = 0;
  final List<String> probedPaths = [];

  _Host({
    this.signedIn = false,
    this.covered = const [],
    this.routes,
    this.probe,
  });

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
  Stream<ShiftSession?> get sessionChanges => const Stream.empty();

  @override
  Future<ShiftSession?> restore() async => session;

  @override
  Future<({int status, String body})?> proxyRoutes() async {
    routeChecks++;
    return routes;
  }

  @override
  Future<({int status, String body})?> probeProxy(
    String provider, {
    required String path,
    required Map<String, dynamic> body,
    Map<String, String> extraHeaders = const {},
  }) async {
    probedPaths.add(path);
    return probe ?? (status: 200, body: '{}');
  }

  @override
  Future<List<String>> includedProviders() async => covered;

  @override
  Future<Membership> membership() async => const Membership(
        status: MembershipStatus.active,
        plan: 'pro',
        ceilingMicros: 25000000,
        spentMicros: 0,
      );

  @override
  Future<bool> isAdmin() async => false;

  @override
  Future<List<ProviderKeyInfo>> listProviderKeys() async => const [];

  @override
  Future<Set<OAuthProvider>> enabledProviders() async => const {};

  @override
  Uri? oauthUrl(OAuthProvider provider, {required Uri redirectTo}) => null;

  @override
  Future<ShiftSession?> adoptCallback(Uri url) async => null;

  @override
  List<SetupLink> setupLinks() => const [];

  @override
  Future<void> signOut() async {}

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
