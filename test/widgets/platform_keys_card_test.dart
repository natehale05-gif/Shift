import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/backend/shift_backend.dart';
import 'package:shift_ai/core/theme/app_theme.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/account_store.dart';
import 'package:shift_ai/features/settings/platform_keys_card.dart';

/// A backend that answers whatever the test needs it to, including the two
/// answers this card turns on: whether the account is an admin, and what the
/// vault said when a key was posted.
class _FakeBackend implements ShiftBackend {
  bool admin = false;
  BackendException? refuseWith;
  final stored = <String, String>{};

  ShiftSession? _session;
  final _sessions = StreamController<ShiftSession?>.broadcast();

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
  Future<void> grantMembership({
    String? email,
    String status = 'active',
    String plan = 'granted',
    required int ceilingMicros,
  }) async {
    if (refuseGrant != null) throw refuseGrant!;
    grants.add((email: email, status: status, ceilingMicros: ceilingMicros));
  }

  BackendException? refuseGrant;
  final grants = <({String? email, String status, int ceilingMicros})>[];

  @override
  List<SetupLink> setupLinks() => setupLinkList;

  List<SetupLink> setupLinkList = const [];

  @override
  Future<({int status, String body})?> probeProxy(
    String provider, {
    Map<String, String> extraHeaders = const {},
  }) async =>
      probeAnswer;

  ({int status, String body})? probeAnswer;

  @override
  Future<({Uri base, Map<String, String> headers})?> managedProviderCall(
    String provider,
  ) async =>
      managedCall;

  ({Uri base, Map<String, String> headers})? managedCall;

  @override
  Future<bool> isAdmin() async => admin;

  @override
  Future<void> putPlatformKey({
    required String provider,
    required String secret,
  }) async {
    if (refuseWith != null) throw refuseWith!;
    stored[provider] = secret;
  }

  @override
  Future<List<String>> includedProviders() async => stored.keys.toList();

  @override
  Future<List<ProviderKeyInfo>> listProviderKeys() async => const [];

  @override
  Future<Membership> membership() async => Membership.none;

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
        home: const Scaffold(body: PlatformKeysCard()),
      ),
    );

void main() {
  testWidgets('an ordinary member never sees it', (tester) async {
    final backend = _FakeBackend();
    final store = await _signedIn(backend);
    await tester.pumpWidget(_host(store));
    await tester.pumpAndSettle();

    expect(find.text('Included with membership'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    store.dispose();
    backend.dispose();
  });

  testWidgets('an admin can paste a key, and it is sent once', (tester) async {
    final backend = _FakeBackend()..admin = true;
    final store = await _signedIn(backend);
    await tester.pumpWidget(_host(store));
    await tester.pumpAndSettle();

    expect(find.text('Included with membership'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'sk-ant-secret-value');
    await tester.tap(find.widgetWithText(FilledButton, 'Save key'));
    await tester.pumpAndSettle();

    expect(backend.stored['anthropic'], 'sk-ant-secret-value');
  });

  testWidgets('the field is cleared on success and kept on failure',
      (tester) async {
    // Kept on failure on purpose: clearing it means pasting a long secret
    // again from a phone, and the paste is the part most likely to go wrong.
    final backend = _FakeBackend()
      ..admin = true
      ..refuseWith = const BackendException(
          BackendProblem.notSignedIn, 'Not allowed.');
    final store = await _signedIn(backend);
    await tester.pumpWidget(_host(store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'sk-ant-rejected');
    await tester.tap(find.widgetWithText(FilledButton, 'Save key'));
    await tester.pumpAndSettle();

    expect(find.text('Not allowed.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'sk-ant-rejected',
    );

    backend.refuseWith = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Save key'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    store.dispose();
    backend.dispose();
  });

  testWidgets('the secret is never rendered', (tester) async {
    final backend = _FakeBackend()..admin = true;
    final store = await _signedIn(backend);
    await tester.pumpWidget(_host(store));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byType(TextField)).obscureText, isTrue);
    store.dispose();
    backend.dispose();
  });
}
