import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/backend/no_backend.dart';
import 'package:shift_ai/backend/shift_backend.dart';

void main() {
  group('NoBackend — the state every build is in today', () {
    test('reports itself unconfigured and signed out', () {
      final backend = NoBackend();
      expect(backend.isConfigured, isFalse);
      expect(backend.session, isNull);
      backend.dispose();
    });

    test('reads answer empty rather than failing', () async {
      // "You have no keys on a server" and "you have no membership" are true
      // answers for someone who never made an account. Throwing here would
      // put an error on screen for the app working exactly as intended.
      final backend = NoBackend();

      expect(await backend.restore(), isNull);
      expect(await backend.listProviderKeys(), isEmpty);
      expect(await backend.listScheduledTasks(), isEmpty);
      expect((await backend.membership()).status, MembershipStatus.none);

      backend.dispose();
    });

    test('signing out of nothing is not an error', () async {
      final backend = NoBackend();
      await expectLater(backend.signOut(), completes);
      backend.dispose();
    });

    test('writes refuse loudly — a key nobody stored must never look saved',
        () async {
      final backend = NoBackend();

      for (final call in <Future<void> Function()>[
        () => backend.signIn(email: 'a@test', password: 'x'),
        () => backend.signUp(email: 'a@test', password: 'x'),
        () => backend.putProviderKey(provider: 'anthropic', secret: 'sk-x'),
        () => backend.deleteProviderKey('k1'),
        () => backend.billingPortal(),
        () => backend.saveScheduledTask(const ScheduledTask(
            id: '', name: 'x', cron: '0 8 * * *', prompt: 'x')),
        () => backend.deleteScheduledTask('t1'),
      ]) {
        await expectLater(
          call(),
          throwsA(isA<BackendException>().having(
              (e) => e.problem, 'problem', BackendProblem.notConfigured)),
        );
      }

      backend.dispose();
    });
  });

  group('ShiftSession', () {
    test('is treated as expired a minute early, so a token cannot die in '
        'flight', () {
      final almost = ShiftSession(
        account: const ShiftAccount(id: 'u1'),
        accessToken: 't',
        expiresAt: DateTime.now().add(const Duration(seconds: 30)),
      );
      final fine = ShiftSession(
        account: const ShiftAccount(id: 'u1'),
        accessToken: 't',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      );

      expect(almost.isExpired, isTrue);
      expect(fine.isExpired, isFalse);
    });

    test('round-trips through JSON', () {
      final session = ShiftSession(
        account: const ShiftAccount(id: 'u1', email: 'a@test', displayName: 'A'),
        accessToken: 'tok',
        refreshToken: 'ref',
        expiresAt: DateTime(2026, 8, 1, 12),
      );

      final restored = ShiftSession.fromJson(session.toJson())!;
      expect(restored.account.id, 'u1');
      expect(restored.account.email, 'a@test');
      expect(restored.accessToken, 'tok');
      expect(restored.refreshToken, 'ref');
      expect(restored.expiresAt, DateTime(2026, 8, 1, 12));
    });

    test('a truncated stored session restores as nothing, not as a broken '
        'one', () {
      // Half a session is worse than none: it would authorize requests with a
      // token that is missing the account it belongs to.
      expect(ShiftSession.fromJson(null), isNull);
      expect(ShiftSession.fromJson({'id': 'u1'}), isNull);
      expect(ShiftSession.fromJson({'accessToken': 't'}), isNull);
      expect(
        ShiftSession.fromJson({'id': 'u1', 'accessToken': 't'}),
        isNull,
        reason: 'no expiry means we cannot know when to refresh',
      );
    });
  });

  group('Membership', () {
    test('no membership cannot spend managed keys', () {
      expect(Membership.none.canSpendManaged, isFalse);
    });

    test('an active membership under its ceiling can', () {
      const member = Membership(
        status: MembershipStatus.active,
        ceilingMicros: 10000000,
        spentMicros: 2500000,
      );
      expect(member.canSpendManaged, isTrue);
      expect(member.fractionUsed, closeTo(0.25, 0.001));
    });

    test('at the ceiling it cannot, which is the point of having one', () {
      const member = Membership(
        status: MembershipStatus.active,
        ceilingMicros: 10000000,
        spentMicros: 10000000,
      );
      expect(member.canSpendManaged, isFalse);
      expect(member.fractionUsed, 1);
    });

    test('a lapsed membership cannot spend even with room left', () {
      const member = Membership(
        status: MembershipStatus.pastDue,
        ceilingMicros: 10000000,
        spentMicros: 0,
      );
      expect(member.canSpendManaged, isFalse);
    });

    test('a zero ceiling reports no usage rather than dividing by zero', () {
      expect(const Membership(status: MembershipStatus.active).fractionUsed, 0);
    });
  });
}
