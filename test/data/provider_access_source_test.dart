import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/backend/shift_backend.dart';
import 'package:shift/data/account_store.dart';
import 'package:shift/data/api_keys_store.dart';
import 'package:shift/data/kv_store.dart';
import 'package:shift/data/provider_access_source.dart';
import 'package:shift/providers/access.dart';

/// Whether a membership can pay for a call, which until now it could not.
///
/// The reported bug in one line: every surface resolved credentials from
/// [ApiKeysStore] alone, so a member with SHIFT's keys on the server and none
/// on their device was told *"No provider is set up"* — routing never asked the
/// account, so the vault, the plan and the metered proxy were unreachable. The
/// first test here is that exact case and is red without the fix.
void main() {
  late Directory dir;
  late ApiKeysStore keys;

  // A real store on a real file, as the other key suites use: what is under
  // test is which credential wins, and a fake map would answer that just as
  // well — but the real one also proves nothing here depends on a stub.
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('shift-access');
    keys = ApiKeysStore(KvStore(path: '${dir.path}/settings.json'));
    await keys.load();
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<AccountStore> signedIn(Host host) async {
    final store = AccountStore(backend: host);
    await store.restore();
    // `refresh` is what reads the plan. Awaited rather than left to the
    // unawaited call inside `restore`, so these assert the answer and not the
    // moment before it.
    await store.refresh();
    return store;
  }

  group('the reported bug', () {
    test('a plan covering a provider makes it usable with no key on the device',
        () async {
      // Red before the fix: `usable` consulted only `keys.has`, so routing
      // found nothing and the turn failed claiming nothing was set up.
      final account = await signedIn(Host(covers: {'openai'}));
      final source = ProviderAccessSource(keys: keys, account: account);

      expect(source.usable('openai'), isTrue);
      expect(keys.has('openai'), isFalse, reason: 'nothing on this device');
    });

    test('and the call goes through the proxy, not to the provider', () async {
      final account = await signedIn(Host(covers: {'openai'}));
      final source = ProviderAccessSource(keys: keys, account: account);

      final access = await source.access('openai');
      expect(access, isA<ManagedAccess>());
      expect((access as ManagedAccess).base.path, contains('provider-proxy'));
      expect(access.headers, contains('Authorization'));
    });
  });

  group('which credential', () {
    test('membership first, even when the user also has their own key',
        () async {
      // They pay monthly, so the plan is what should be spent.
      await keys.set('openai', 'sk-own');
      final account = await signedIn(Host(covers: {'openai'}));

      expect(
        await ProviderAccessSource(keys: keys, account: account)
            .access('openai'),
        isA<ManagedAccess>(),
      );
    });

    test('over the ceiling falls back to their own key', () async {
      // Degrade, not stop: hitting the ceiling should cost them the plan for
      // that call, not the turn.
      await keys.set('openai', 'sk-own');
      final account = await signedIn(Host(covers: {'openai'}, spent: true));
      final source = ProviderAccessSource(keys: keys, account: account);

      expect(source.usable('openai'), isTrue);
      expect(await source.access('openai'), isA<DirectKey>());
    });

    test('a provider outside the plan uses their own key', () async {
      await keys.set('gemini', 'g-own');
      final account = await signedIn(Host(covers: {'openai'}));

      expect(
        await ProviderAccessSource(keys: keys, account: account)
            .access('gemini'),
        isA<DirectKey>(),
      );
    });

    test('a proxy that cannot be reached falls back rather than failing',
        () async {
      // A ManagedAccess with no token is a request sent with no credential,
      // and the 401 it earns reads as a bad key.
      await keys.set('openai', 'sk-own');
      final account =
          await signedIn(Host(covers: {'openai'}, proxyDown: true));

      expect(
        await ProviderAccessSource(keys: keys, account: account)
            .access('openai'),
        isA<DirectKey>(),
      );
    });

    test('signed out asks the server nothing at all', () async {
      // "It worked" and "it worked without a wasted round trip" have to be
      // distinguishable, so the fake counts.
      await keys.set('openai', 'sk-own');
      final host = Host(covers: {'openai'});
      final account = AccountStore(backend: host);

      final access =
          await ProviderAccessSource(keys: keys, account: account)
              .access('openai');

      expect(access, isA<DirectKey>());
      expect(host.proxyCalls, 0);
    });

    test('no plan and no key is null, which is a state and not an error',
        () async {
      final account = await signedIn(Host(planned: false));
      expect(
        await ProviderAccessSource(keys: keys, account: account)
            .access('openai'),
        isNull,
      );
    });

    test('with no account at all it is exactly the old behaviour', () async {
      // A build with no server behind it still works on device keys.
      await keys.set('openai', 'sk-own');
      final source = ProviderAccessSource.deviceOnly(keys);

      expect(source.usable('openai'), isTrue);
      expect(source.usable('gemini'), isFalse);
      expect(await source.access('openai'), isA<DirectKey>());
    });
  });

  group('what it says when it cannot', () {
    test('a plan that could not be read never claims there is no plan',
        () async {
      // `refresh` swallows its failures on purpose, so without this a network
      // blip tells a paying member to start a plan.
      final account = AccountStore(backend: Host(covers: {'openai'}, dead: true));
      await account.restore();
      await account.refresh();

      final source = ProviderAccessSource(keys: keys, account: account);
      expect(source.entitlement.known, isFalse);
      expect(source.explain('images'), contains("Couldn't check"));
      expect(source.explain('images'), isNot(contains('do not have an active')));
    });

    test('a spent plan is told apart from no plan', () async {
      final spent = ProviderAccessSource(
        keys: keys,
        account: await signedIn(Host(covers: {'openai'}, spent: true)),
      );
      final none = ProviderAccessSource(
        keys: keys,
        account: await signedIn(Host(planned: false)),
      );

      expect(spent.explain('images'), contains("this month's allowance"));
      expect(none.explain('images'), contains('do not have an active plan'));
      expect(spent.explain('images'), isNot(none.explain('images')));
    });

    test('a plan that simply does not cover this says so', () async {
      final source = ProviderAccessSource(
        keys: keys,
        account: await signedIn(Host(covers: {'anthropic'})),
      );
      expect(source.explain('images'), contains("doesn't cover images"));
    });
  });
}

/// A configured host with a plan the test describes.
class Host implements ShiftBackend {
  /// Providers the plan covers.
  final Set<String> covers;

  /// Active, but the meter is at its ceiling.
  final bool spent;

  /// The proxy cannot hand back a target.
  final bool proxyDown;

  /// Reading the plan fails, which `refresh` swallows.
  final bool dead;

  /// Whether there is a subscription at all.
  ///
  /// Distinct from `covers: {}`, which is an *active* plan that happens to
  /// cover nothing — a different state needing a different sentence, and the
  /// distinction this fake originally blurred.
  final bool planned;

  /// Counts proxy round trips, so a wasted one is visible.
  int proxyCalls = 0;

  Host({
    this.covers = const {},
    this.spent = false,
    this.proxyDown = false,
    this.dead = false,
    this.planned = true,
  });

  @override
  bool get isConfigured => true;

  @override
  ShiftSession? get session => ShiftSession(
        account: const ShiftAccount(id: 'u1', email: 'a@example.com'),
        accessToken: 'token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

  @override
  Future<ShiftSession?> restore() async => session;

  @override
  Stream<ShiftSession?> get sessionChanges => const Stream.empty();

  @override
  Future<Membership> membership() async {
    if (dead) throw StateError('cannot read the plan');
    if (!planned) return Membership.none;
    return Membership(
      status: MembershipStatus.active,
      plan: 'test',
      ceilingMicros: 1000000,
      spentMicros: spent ? 1000000 : 0,
    );
  }

  @override
  Future<List<String>> includedProviders() async {
    if (dead) throw StateError('cannot read the plan');
    return covers.toList();
  }

  @override
  Future<({Uri base, Map<String, String> headers})?> managedProviderCall(
    String provider,
  ) async {
    proxyCalls++;
    if (proxyDown) return null;
    return (
      base: Uri.parse('https://host.test/functions/v1/provider-proxy/$provider'),
      headers: const {'Authorization': 'Bearer session-token'},
    );
  }

  @override
  Future<List<ProviderKeyInfo>> listProviderKeys() async => const [];

  @override
  Future<bool> isAdmin() async => false;

  @override
  Future<Set<OAuthProvider>> enabledProviders() async => const {};

  @override
  Uri? oauthUrl(OAuthProvider provider, {required Uri redirectTo}) => null;

  @override
  Future<ShiftSession?> adoptCallback(Uri url) async => null;

  @override
  List<SetupLink> setupLinks() => const [];

  @override
  void dispose() {}

  // Nothing below is reached.
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
  Future<void> grantMembership({
    String? email,
    String status = 'active',
    String plan = 'granted',
    required int ceilingMicros,
  }) =>
      throw UnimplementedError();

  @override
  Future<({int status, String body})?> proxyRoutes() async => null;

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
