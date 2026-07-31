import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shift_ai/backend/no_backend.dart';
import 'package:shift_ai/backend/shift_backend.dart';
import 'package:shift_ai/data/persistence/persistence_service.dart';
import 'package:shift_ai/data/stores/account_store.dart';

/// A backend whose every outcome the test dictates, so the store's states can
/// be driven directly rather than inferred from a real server's behaviour.
class _FakeBackend implements ShiftBackend {
  @override
  bool get isConfigured => true;

  ShiftSession? _session;
  final _sessions = StreamController<ShiftSession?>.broadcast();

  ShiftSession? storedSession;
  BackendException? failWith;
  Membership membershipValue = Membership.none;
  List<ProviderKeyInfo> keys = const [];
  int signOutCalls = 0;
  int membershipCalls = 0;
  List<String> storedSecrets = [];

  @override
  ShiftSession? get session => _session;

  @override
  Stream<ShiftSession?> get sessionChanges => _sessions.stream;

  ShiftSession _sessionFor(String email) => ShiftSession(
        account: ShiftAccount(id: 'u1', email: email),
        accessToken: 'tok',
        refreshToken: 'ref',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

  @override
  Future<ShiftSession?> restore() async {
    if (failWith != null) throw failWith!;
    _session = storedSession;
    return storedSession;
  }

  @override
  Future<ShiftSession> signIn({
    required String email,
    required String password,
  }) async {
    if (failWith != null) throw failWith!;
    _session = _sessionFor(email);
    _sessions.add(_session);
    return _session!;
  }

  @override
  Future<ShiftSession> signUp({
    required String email,
    required String password,
  }) async {
    if (failWith != null) throw failWith!;
    _session = _sessionFor(email);
    _sessions.add(_session);
    return _session!;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (failWith != null) throw failWith!;
    _session = null;
    _sessions.add(null);
  }

  @override
  Future<List<ProviderKeyInfo>> listProviderKeys() async => keys;

  @override
  Future<ProviderKeyInfo> putProviderKey({
    required String provider,
    required String secret,
  }) async {
    if (failWith != null) throw failWith!;
    storedSecrets.add(secret);
    return ProviderKeyInfo(
      id: 'k1',
      provider: provider,
      lastFour: secret.substring(secret.length - 4),
      managed: false,
      addedAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteProviderKey(String id) async {
    if (failWith != null) throw failWith!;
  }

  List<String> platformSecrets = [];

  @override
  Future<void> putPlatformKey({
    required String provider,
    required String secret,
  }) async {
    if (failWith != null) throw failWith!;
    platformSecrets.add(secret);
  }

  @override
  Future<List<String>> includedProviders() async => included;

  List<String> included = const [];

  bool adminValue = false;

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
  Future<({int status, String body})?> probeProxy(String provider) async =>
      probeAnswer;

  ({int status, String body})? probeAnswer;

  @override
  Future<({Uri base, Map<String, String> headers})?> managedProviderCall(
    String provider,
  ) async =>
      managedCall;

  ({Uri base, Map<String, String> headers})? managedCall;

  @override
  Future<bool> isAdmin() async => adminValue;

  @override
  Future<Membership> membership() async {
    membershipCalls++;
    return membershipValue;
  }

  @override
  Future<Uri> billingPortal({String? plan}) async =>
      Uri.parse('https://billing.test');

  @override
  Future<List<ScheduledTask>> listScheduledTasks() async => const [];

  @override
  Future<ScheduledTask> saveScheduledTask(ScheduledTask task) async => task;

  @override
  Future<void> deleteScheduledTask(String id) async {}

  @override
  void dispose() => _sessions.close();
}

AccountStore _store(ShiftBackend backend) {
  SharedPreferences.setMockInitialValues({});
  return AccountStore(backend: backend, persistence: PersistenceService());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('with no server configured', () {
    test('settles to signed out and reports itself unconfigured', () async {
      final store = _store(NoBackend());
      expect(store.isConfigured, isFalse);

      await store.restore();

      expect(store.phase, AccountPhase.signedOut);
      expect(store.account, isNull);
      store.dispose();
    });

    test('signing in fails with a sentence rather than an exception', () async {
      // The UI shows `problem`; nothing above the store catches.
      final store = _store(NoBackend());
      await store.restore();

      final ok = await store.signIn(email: 'a@test', password: 'pw');

      expect(ok, isFalse);
      expect(store.problem, isNotNull);
      expect(store.phase, AccountPhase.signedOut);
      store.dispose();
    });
  });

  group('restore', () {
    test('starts in checking, so a launch does not flash "signed out" at '
        'someone who is signed in', () async {
      final backend = _FakeBackend();
      final store = _store(backend);

      // Before restore() has been awaited.
      expect(store.phase, AccountPhase.checking);

      store.dispose();
      backend.dispose();
    });

    test('a stored session comes back signed in', () async {
      final backend = _FakeBackend()
        ..storedSession = ShiftSession(
          account: const ShiftAccount(id: 'u1', email: 'a@test'),
          accessToken: 'tok',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
        );
      final store = _store(backend);

      await store.restore();

      expect(store.phase, AccountPhase.signedIn);
      expect(store.account?.email, 'a@test');
      store.dispose();
      backend.dispose();
    });

    test('a failing restore is signed out, not an error on launch', () async {
      // Someone who has not opened the app in a month should meet a sign-in
      // screen, not a red banner.
      final backend = _FakeBackend()
        ..failWith = const BackendException(
            BackendProblem.unavailable, 'network down');
      final store = _store(backend);

      await store.restore();

      expect(store.phase, AccountPhase.signedOut);
      expect(store.problem, isNull, reason: 'restoring is not a user action');
      store.dispose();
      backend.dispose();
    });
  });

  group('signing in', () {
    test('succeeds and then loads membership in the background', () async {
      final backend = _FakeBackend()
        ..membershipValue = const Membership(
          status: MembershipStatus.active,
          plan: 'pro',
          ceilingMicros: 10000000,
          spentMicros: 2500000,
        );
      final store = _store(backend);
      await store.restore();

      final ok = await store.signIn(email: 'a@test', password: 'pw');
      expect(ok, isTrue);
      expect(store.phase, AccountPhase.signedIn);
      expect(store.problem, isNull);

      await Future<void>.delayed(Duration.zero);
      expect(backend.membershipCalls, greaterThan(0));
      expect(store.membership.canSpendManaged, isTrue);
      store.dispose();
      backend.dispose();
    });

    test('a wrong password leaves the form usable with the reason shown',
        () async {
      final backend = _FakeBackend()
        ..failWith = const BackendException(
            BackendProblem.credentials, 'That email and password did not match.');
      final store = _store(backend);
      await store.restore();

      final ok = await store.signIn(email: 'a@test', password: 'nope');

      expect(ok, isFalse);
      expect(store.phase, AccountPhase.signedOut,
          reason: 'not stuck in working — the button must come back');
      expect(store.problem, contains('did not match'));
      store.dispose();
      backend.dispose();
    });

    test('a retry clears the previous error before it starts', () async {
      // A stale message sitting under a form that has since worked is its own
      // small lie.
      final backend = _FakeBackend()
        ..failWith =
            const BackendException(BackendProblem.credentials, 'wrong');
      final store = _store(backend);
      await store.restore();
      await store.signIn(email: 'a@test', password: 'nope');
      expect(store.problem, 'wrong');

      backend.failWith = null;
      final ok = await store.signIn(email: 'a@test', password: 'right');

      expect(ok, isTrue);
      expect(store.problem, isNull);
      store.dispose();
      backend.dispose();
    });

    test('creating an account is the same path with a different call',
        () async {
      final backend = _FakeBackend();
      final store = _store(backend);
      await store.restore();

      expect(await store.signUp(email: 'new@test', password: 'pw12345678'),
          isTrue);
      expect(store.account?.email, 'new@test');
      store.dispose();
      backend.dispose();
    });

    test('an account awaiting email confirmation is a notice, not an error',
        () async {
      // The account was created. Showing this in red under the form reads as
      // "that did not work" and invites a second attempt, which then fails
      // with "already registered" — the worst possible sequence for someone
      // who did everything right.
      final backend = _FakeBackend()
        ..failWith = BackendException(
          BackendProblem.confirmationRequired,
          defaultMessageFor(BackendProblem.confirmationRequired),
        );
      final store = _store(backend);
      await store.restore();

      expect(await store.signUp(email: 'new@test', password: 'pw12345678'),
          isFalse);
      expect(store.problem, isNull);
      expect(store.notice, contains('Check your email'));
      store.dispose();
      backend.dispose();
    });

    test('a failure that is not a confirmation still shows as one', () async {
      final backend = _FakeBackend()
        ..failWith = const BackendException(
            BackendProblem.credentials, 'That email is already registered.');
      final store = _store(backend);
      await store.restore();

      expect(await store.signUp(email: 'taken@test', password: 'pw12345678'),
          isFalse);
      expect(store.problem, 'That email is already registered.');
      expect(store.notice, isNull);
      store.dispose();
      backend.dispose();
    });
  });

  group('admin', () {
    test('comes from the server, and is false until it has been asked',
        () async {
      final backend = _FakeBackend()..adminValue = true;
      final store = _store(backend);
      await store.restore();

      // Before signing in there is nobody to be an admin.
      expect(store.isAdmin, isFalse);

      await store.signIn(email: 'a@test', password: 'pw');
      await store.refresh();
      expect(store.isAdmin, isTrue);

      store.dispose();
      backend.dispose();
    });

    test('an ordinary account is not one', () async {
      final backend = _FakeBackend();
      final store = _store(backend);
      await store.restore();
      await store.signIn(email: 'a@test', password: 'pw');
      await store.refresh();

      expect(store.isAdmin, isFalse);
      store.dispose();
      backend.dispose();
    });

    test('signing out gives it up', () async {
      final backend = _FakeBackend()..adminValue = true;
      final store = _store(backend);
      await store.restore();
      await store.signIn(email: 'a@test', password: 'pw');
      await store.refresh();
      expect(store.isAdmin, isTrue);

      await store.signOut();
      expect(store.isAdmin, isFalse);
      store.dispose();
      backend.dispose();
    });
  });

  group('signing out', () {
    test('clears the account, the membership and the keys', () async {
      final backend = _FakeBackend()
        ..membershipValue = const Membership(status: MembershipStatus.active)
        ..keys = [
          ProviderKeyInfo(
            id: 'k1',
            provider: 'anthropic',
            lastFour: '1234',
            managed: false,
            addedAt: DateTime(2026),
          )
        ];
      final store = _store(backend);
      await store.restore();
      await store.signIn(email: 'a@test', password: 'pw');
      await store.refresh();
      expect(store.serverKeys, hasLength(1));

      await store.signOut();

      expect(store.phase, AccountPhase.signedOut);
      expect(store.account, isNull);
      expect(store.membership.status, MembershipStatus.none);
      expect(store.serverKeys, isEmpty);
      store.dispose();
      backend.dispose();
    });

    test('succeeds locally even when telling the server fails', () async {
      // A network blip must not strand somebody signed in on a device they
      // wanted to leave.
      final backend = _FakeBackend();
      final store = _store(backend);
      await store.restore();
      await store.signIn(email: 'a@test', password: 'pw');

      backend.failWith =
          const BackendException(BackendProblem.unavailable, 'offline');
      await store.signOut();

      expect(backend.signOutCalls, 1);
      expect(store.phase, AccountPhase.signedOut);
      store.dispose();
      backend.dispose();
    });
  });

  group('storing a provider key', () {
    test('sends the secret and returns null on success', () async {
      final backend = _FakeBackend();
      final store = _store(backend);
      await store.restore();
      await store.signIn(email: 'a@test', password: 'pw');

      final error = await store.putProviderKey(
          provider: 'anthropic', secret: 'sk-ant-abcdwxyz');

      expect(error, isNull);
      expect(backend.storedSecrets, ['sk-ant-abcdwxyz']);
      store.dispose();
      backend.dispose();
    });

    test('returns the reason rather than throwing at the widget', () async {
      final backend = _FakeBackend();
      final store = _store(backend);
      await store.restore();
      await store.signIn(email: 'a@test', password: 'pw');

      backend.failWith = const BackendException(
          BackendProblem.overLimit, 'ceiling reached');
      final error = await store.putProviderKey(
          provider: 'anthropic', secret: 'sk-ant-abcdwxyz');

      expect(error, 'ceiling reached');
      store.dispose();
      backend.dispose();
    });
  });

  test('a background refresh that fails leaves the last good values alone',
      () async {
    // This runs unprompted after sign-in; an error banner for something
    // nobody asked for is noise.
    final backend = _FakeBackend()
      ..membershipValue = const Membership(
          status: MembershipStatus.active, plan: 'pro');
    final store = _store(backend);
    await store.restore();
    await store.signIn(email: 'a@test', password: 'pw');
    await store.refresh();
    expect(store.membership.plan, 'pro');

    backend.failWith =
        const BackendException(BackendProblem.unavailable, 'offline');
    await store.refresh();

    expect(store.membership.plan, 'pro');
    expect(store.problem, isNull);
    store.dispose();
    backend.dispose();
  });
}
