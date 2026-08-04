import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/backend/shift_backend.dart';
import 'package:shift_ai/core/theme/app_theme.dart';
import 'package:shift_ai/core/theme/tap_targets.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/account_store.dart';
import 'package:shift_ai/features/settings/setup_card.dart';

class _FakeBackend implements ShiftBackend {
  bool admin = false;
  Membership membershipValue = Membership.none;
  ({int status, String body})? probeAnswer;
  BackendException? refuseGrant;
  final grants = <({String? email, String status, int ceilingMicros})>[];

  final _sessions = StreamController<ShiftSession?>.broadcast();
  ShiftSession? _session;

  @override
  bool get isConfigured => true;

  @override
  ShiftSession? get session => _session;

  @override
  Stream<ShiftSession?> get sessionChanges => _sessions.stream;

  @override
  Future<ShiftSession?> restore() async {
    _session = ShiftSession(
      account: const ShiftAccount(id: 'u1', email: 'nate@test'),
      accessToken: 'tok',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    return _session;
  }

  @override
  Future<bool> isAdmin() async => admin;

  @override
  Future<Membership> membership() async => membershipValue;

  @override
  List<SetupLink> setupLinks() => [
        SetupLink(
          title: 'A host setting only a dashboard can change',
          action: 'Open it',
          url: Uri.parse('https://example.test/settings'),
          copyLabel: 'Value',
          copyValue: 'paste-me',
        ),
      ];

  @override
  Future<({int status, String body})?> probeProxy(
    String provider, {
    Map<String, String> extraHeaders = const {},
  }) async =>
      probeAnswer;

  @override
  Future<void> grantMembership({
    String? email,
    String status = 'active',
    String plan = 'granted',
    required int ceilingMicros,
  }) async {
    if (refuseGrant != null) throw refuseGrant!;
    grants.add((email: email, status: status, ceilingMicros: ceilingMicros));
    membershipValue = Membership(
      status: MembershipStatus.active,
      plan: plan,
      ceilingMicros: ceilingMicros,
    );
  }

  @override
  Future<List<String>> includedProviders() async => const ['anthropic'];

  @override
  Future<List<ProviderKeyInfo>> listProviderKeys() async => const [];

  @override
  Future<({Uri base, Map<String, String> headers})?> managedProviderCall(
    String provider,
  ) async =>
      null;

  @override
  Future<ShiftSession> signIn({
    required String email,
    required String password,
  }) async =>
      throw UnimplementedError();

  @override
  Future<ShiftSession> signUp({
    required String email,
    required String password,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> signOut() async {}

  @override
  Future<ProviderKeyInfo> putProviderKey({
    required String provider,
    required String secret,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> putPlatformKey({
    required String provider,
    required String secret,
  }) async {}

  @override
  Future<void> deleteProviderKey(String id) async {}

  @override
  Future<Uri> billingPortal({String? plan}) async => Uri.parse('https://x');

  @override
  Future<List<ScheduledTask>> listScheduledTasks() async => const [];

  @override
  Future<ScheduledTask> saveScheduledTask(ScheduledTask task) async => task;

  @override
  Future<void> deleteScheduledTask(String id) async {}

  @override
  void dispose() => _sessions.close();
}

Future<AccountStore> _signedIn(_FakeBackend backend) async {
  SharedPreferences.setMockInitialValues({});
  final store =
      AccountStore(backend: backend, persistence: PersistenceService());
  await store.restore();
  await store.refresh();
  return store;
}

Widget _host(AccountStore store) => ChangeNotifierProvider<AccountStore>.value(
      value: store,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: SingleChildScrollView(child: SetupCard())),
      ),
    );

void main() {
  testWidgets('an ordinary member never sees it', (tester) async {
    final backend = _FakeBackend();
    final store = await _signedIn(backend);
    await tester.pumpWidget(_host(store));
    await tester.pump();

    expect(find.text('Server setup'), findsNothing);
    store.dispose();
    backend.dispose();
  });

  testWidgets('an untested proxy is shown as unknown, not as broken',
      (tester) async {
    // A red cross for something never checked sends someone to fix what was
    // never wrong.
    final backend = _FakeBackend()..admin = true;
    final store = await _signedIn(backend);
    await tester.pumpWidget(_host(store));
    await tester.pump();

    expect(find.text('Not tested yet'), findsOneWidget);
  });

  testWidgets('the test button reports what the server actually said',
      (tester) async {
    final backend = _FakeBackend()
      ..admin = true
      ..probeAnswer = (status: 404, body: '');
    final store = await _signedIn(backend);
    await tester.pumpWidget(_host(store));
    await tester.pump();

    await tester.tap(find.text('Run test'));
    await tester.pumpAndSettle();

    expect(find.textContaining('not deployed'), findsOneWidget);
    store.dispose();
    backend.dispose();
  });

  testWidgets('a working proxy reads as working', (tester) async {
    final backend = _FakeBackend()
      ..admin = true
      ..probeAnswer = (status: 200, body: 'data: {}');
    final store = await _signedIn(backend);
    await tester.pumpWidget(_host(store));
    await tester.pump();

    await tester.tap(find.text('Run test'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Working'), findsOneWidget);
    store.dispose();
    backend.dispose();
  });

  testWidgets('granting a plan sends dollars as micros', (tester) async {
    // The unit boundary: a person types 25, the meter counts in millionths.
    // Getting this wrong by a factor of a million is the obvious way for a
    // \$25 cap to become a \$0.000025 one — or a \$25,000,000 one.
    final backend = _FakeBackend()..admin = true;
    final store = await _signedIn(backend);
    await tester.pumpWidget(_host(store));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, '25');
    await tester.tap(find.text('Grant'));
    await tester.pumpAndSettle();

    expect(backend.grants.single.ceilingMicros, 25000000);
    store.dispose();
    backend.dispose();
  });

  testWidgets('a refused grant shows the server\'s reason', (tester) async {
    final backend = _FakeBackend()
      ..admin = true
      ..refuseGrant = const BackendException(
          BackendProblem.notSignedIn, 'Not allowed.');
    final store = await _signedIn(backend);
    await tester.pumpWidget(_host(store));
    await tester.pump();

    await tester.tap(find.text('Grant'));
    await tester.pumpAndSettle();

    expect(find.text('Not allowed.'), findsOneWidget);
    store.dispose();
    backend.dispose();
  });

  testWidgets('a non-numeric cap is refused before any request', (tester) async {
    final backend = _FakeBackend()..admin = true;
    final store = await _signedIn(backend);
    await tester.pumpWidget(_host(store));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'lots');
    await tester.tap(find.text('Grant'));
    await tester.pumpAndSettle();

    expect(backend.grants, isEmpty);
    expect(find.textContaining('dollars'), findsWidgets);
    store.dispose();
    backend.dispose();
  });

  testWidgets('every control clears the minimum tap target', (tester) async {
    // This card exists to be used on a phone; a 32pt button on one would be
    // the joke writing itself.
    final backend = _FakeBackend()..admin = true;
    final store = await _signedIn(backend);
    await tester.pumpWidget(_host(store));
    await tester.pump();

    // By predicate rather than by type: `FilledButton.icon` builds a private
    // subclass, so `byType(FilledButton)` silently matches none of them — and
    // a tap-target test that finds no targets passes without checking
    // anything, which is the worst kind of green.
    final buttons = find.byWidgetPredicate((w) => w is ButtonStyleButton);
    expect(buttons, findsWidgets, reason: 'the card has buttons to measure');

    for (final element in buttons.evaluate()) {
      expect(element.size!.height, greaterThanOrEqualTo(kMinTouchTarget),
          reason: '${element.widget.runtimeType} is only '
              '${element.size!.height} tall');
    }
    store.dispose();
    backend.dispose();
  });
}
