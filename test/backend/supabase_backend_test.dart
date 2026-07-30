import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shift_ai/backend/backend_config.dart';
import 'package:shift_ai/backend/shift_backend.dart';
import 'package:shift_ai/backend/supabase_backend.dart';

const _config = BackendConfig(url: 'https://x.test', anonKey: 'anon-key');

/// A signed-in response, the shape GoTrue actually returns.
String _tokenBody({int expiresIn = 3600, String token = 'access-1'}) =>
    jsonEncode({
      'access_token': token,
      'refresh_token': 'refresh-1',
      'expires_in': expiresIn,
      'user': {
        'id': '11111111-1111-1111-1111-111111111111',
        'email': 'a@test',
        'user_metadata': {'name': 'Nate'},
      },
    });

/// Records every request so a test can assert what was sent, not only what
/// came back — "did it reach the edge function or write the table directly"
/// is the security-relevant question and it is invisible in the return value.
class _Recorder {
  final List<http.Request> requests = [];

  MockClient client(
      Future<http.Response> Function(http.Request request) handler) {
    return MockClient((request) async {
      requests.add(request);
      return handler(request);
    });
  }

  http.Request get last => requests.last;
  Iterable<String> get paths => requests.map((r) => r.url.path);
}

SupabaseBackend _backend(
  MockClient client, {
  ShiftSession? stored,
  void Function(ShiftSession?)? onChanged,
}) =>
    SupabaseBackend(
      config: _config,
      client: client,
      loadStoredSession: () async => stored,
      onSessionChanged: (s) async => onChanged?.call(s),
    );

Future<SupabaseBackend> _signedIn(MockClient client) async {
  final backend = _backend(client);
  await backend.signIn(email: 'a@test', password: 'pw');
  return backend;
}

void main() {
  group('sign in', () {
    test('parses the session and reports it', () async {
      final recorder = _Recorder();
      final backend = _backend(
          recorder.client((_) async => http.Response(_tokenBody(), 200)));

      final session = await backend.signIn(email: 'a@test', password: 'pw');

      expect(session.account.id, '11111111-1111-1111-1111-111111111111');
      expect(session.account.email, 'a@test');
      expect(session.account.displayName, 'Nate');
      expect(session.accessToken, 'access-1');
      expect(backend.session, isNotNull);
      expect(recorder.last.url.queryParameters['grant_type'], 'password');
      backend.dispose();
    });

    test('hands the session out to be persisted', () async {
      ShiftSession? saved;
      final recorder = _Recorder();
      final backend = _backend(
        recorder.client((_) async => http.Response(_tokenBody(), 200)),
        onChanged: (s) => saved = s,
      );

      await backend.signIn(email: 'a@test', password: 'pw');
      expect(saved?.accessToken, 'access-1');
      backend.dispose();
    });

    test('a wrong password is a credentials problem, not a crash', () async {
      final recorder = _Recorder();
      final backend = _backend(recorder.client((_) async => http.Response(
          jsonEncode({'error_description': 'Invalid login credentials'}), 400)));

      await expectLater(
        backend.signIn(email: 'a@test', password: 'nope'),
        throwsA(isA<BackendException>()
            .having((e) => e.problem, 'problem', BackendProblem.credentials)
            .having((e) => e.message, 'message',
                contains('Invalid login credentials'))),
      );
      backend.dispose();
    });

    test('being offline is unavailable, not credentials — the difference is '
        'whether the user should retype their password', () async {
      final backend = _backend(MockClient((_) async {
        throw const SocketExceptionStub();
      }));

      await expectLater(
        backend.signIn(email: 'a@test', password: 'pw'),
        throwsA(isA<BackendException>()
            .having((e) => e.problem, 'problem', BackendProblem.unavailable)),
      );
      backend.dispose();
    });

    test('a sign-up needing email confirmation says so instead of looking '
        'like a failure', () async {
      // The project returns a user and no token. Reporting "something went
      // wrong" would send someone to retry an account they already created.
      final backend = _backend(MockClient((_) async => http.Response(
          jsonEncode({'user': {'id': 'u1', 'email': 'a@test'}}), 200)));

      await expectLater(
        backend.signUp(email: 'a@test', password: 'pw'),
        throwsA(isA<BackendException>()
            .having((e) => e.message, 'message', contains('confirm'))),
      );
      backend.dispose();
    });
  });

  group('sessions', () {
    test('a stored session that is still good is adopted without a network '
        'call', () async {
      final recorder = _Recorder();
      final backend = _backend(
        recorder.client((_) async => http.Response('{}', 500)),
        stored: ShiftSession(
          account: const ShiftAccount(id: 'u1'),
          accessToken: 'stored',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 2)),
        ),
      );

      final restored = await backend.restore();
      expect(restored?.accessToken, 'stored');
      expect(recorder.requests, isEmpty);
      backend.dispose();
    });

    test('an expired stored session is refreshed', () async {
      final recorder = _Recorder();
      final backend = _backend(
        recorder.client(
            (_) async => http.Response(_tokenBody(token: 'access-2'), 200)),
        stored: ShiftSession(
          account: const ShiftAccount(id: 'u1'),
          accessToken: 'stale',
          refreshToken: 'r',
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );

      final restored = await backend.restore();
      expect(restored?.accessToken, 'access-2');
      expect(recorder.last.url.queryParameters['grant_type'], 'refresh_token');
      backend.dispose();
    });

    test('a refresh token the server has forgotten means signed out, not an '
        'error on launch', () async {
      // Someone who has not opened the app in a month should see a sign-in
      // screen, not a red banner.
      final backend = _backend(
        MockClient((_) async => http.Response('{}', 401)),
        stored: ShiftSession(
          account: const ShiftAccount(id: 'u1'),
          accessToken: 'stale',
          refreshToken: 'r',
          expiresAt: DateTime.now().subtract(const Duration(hours: 1)),
        ),
      );

      expect(await backend.restore(), isNull);
      expect(backend.session, isNull);
      backend.dispose();
    });

    test('an expiring token is refreshed before the call that needs it, not '
        'after it fails', () async {
      final recorder = _Recorder();
      final backend = _backend(
        recorder.client((request) async {
          if (request.url.path.contains('/auth/')) {
            return http.Response(_tokenBody(token: 'access-2'), 200);
          }
          return http.Response(jsonEncode([]), 200);
        }),
        // Valid for 30 seconds — inside the one-minute safety margin.
        stored: ShiftSession(
          account: const ShiftAccount(id: 'u1'),
          accessToken: 'nearly-dead',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(seconds: 30)),
        ),
      );
      await backend.restore();

      await backend.listProviderKeys();

      expect(recorder.paths.where((p) => p.contains('/auth/')), isNotEmpty,
          reason: 'it refreshed first');
      expect(recorder.last.headers['Authorization'], 'Bearer access-2');
      backend.dispose();
    });

    test('a call while signed out says so rather than sending an anonymous '
        'request', () async {
      final backend = _backend(MockClient((_) async => http.Response('[]', 200)));

      await expectLater(
        backend.listProviderKeys(),
        throwsA(isA<BackendException>()
            .having((e) => e.problem, 'problem', BackendProblem.notSignedIn)),
      );
      backend.dispose();
    });
  });

  group('key vault', () {
    test('lists metadata and never a secret', () async {
      final recorder = _Recorder();
      final backend = await _signedIn(recorder.client((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(_tokenBody(), 200);
        }
        return http.Response(
            jsonEncode([
              {
                'id': 'k1',
                'provider': 'anthropic',
                'key_owner': 'user',
                'last_four': '1234',
                'created_at': '2026-07-30T00:00:00Z',
              },
              {
                'id': 'k2',
                'provider': 'openai',
                'key_owner': 'managed',
                'last_four': '9999',
                'created_at': '2026-07-30T00:00:00Z',
              },
            ]),
            200);
      }));

      final keys = await backend.listProviderKeys();

      expect(keys, hasLength(2));
      expect(keys.first.provider, 'anthropic');
      expect(keys.first.lastFour, '1234');
      expect(keys.first.managed, isFalse);
      expect(keys.last.managed, isTrue);
      // The view, not the table — the table's ciphertext column is not
      // something a client is granted.
      expect(recorder.last.url.path, contains('provider_key_metadata'));
      backend.dispose();
    });

    test('storing a key goes through the edge function, never straight into '
        'the table', () async {
      // The row holds ciphertext. A client that could insert directly would
      // have to hold the encryption key, which is the whole thing the vault
      // exists to avoid.
      final recorder = _Recorder();
      final backend = await _signedIn(recorder.client((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(_tokenBody(), 200);
        }
        return http.Response(jsonEncode({'id': 'k1', 'last_four': 'wxyz'}), 200);
      }));

      final stored =
          await backend.putProviderKey(provider: 'anthropic', secret: 'sk-wxyz');

      expect(recorder.last.url.path, '/functions/v1/provider-key');
      expect(recorder.paths.any((p) => p.contains('/rest/v1/provider_keys')),
          isFalse);
      expect(stored.lastFour, 'wxyz');
      backend.dispose();
    });
  });

  group('membership', () {
    test('no row is "no membership", which is a real state, not a failure',
        () async {
      final backend = await _signedIn(MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(_tokenBody(), 200);
        }
        return http.Response(jsonEncode([]), 200);
      }));

      expect((await backend.membership()).status, MembershipStatus.none);
      backend.dispose();
    });

    test('reads status, ceiling and spend together', () async {
      final backend = await _signedIn(MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(_tokenBody(), 200);
        }
        if (request.url.path.contains('rpc/managed_spend_micros')) {
          return http.Response('2500000', 200);
        }
        return http.Response(
            jsonEncode([
              {
                'status': 'active',
                'plan': 'pro',
                'current_period_end': '2026-08-30T00:00:00Z',
                'spend_ceiling_micros': 10000000,
              }
            ]),
            200);
      }));

      final member = await backend.membership();

      expect(member.status, MembershipStatus.active);
      expect(member.plan, 'pro');
      expect(member.ceilingMicros, 10000000);
      expect(member.spentMicros, 2500000);
      expect(member.canSpendManaged, isTrue);
      backend.dispose();
    });

    test('an unreadable usage figure reports zero spend rather than failing '
        'the whole membership read', () async {
      final backend = await _signedIn(MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(_tokenBody(), 200);
        }
        if (request.url.path.contains('rpc/')) {
          return http.Response('{}', 500);
        }
        return http.Response(
            jsonEncode([
              {'status': 'active', 'spend_ceiling_micros': 10000000}
            ]),
            200);
      }));

      final member = await backend.membership();
      expect(member.status, MembershipStatus.active);
      expect(member.spentMicros, 0);
      backend.dispose();
    });

    test('being over the limit is its own problem — it is the one failure the '
        'user can actually act on', () async {
      final backend = await _signedIn(MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(_tokenBody(), 200);
        }
        return http.Response(jsonEncode({'message': 'ceiling reached'}), 429);
      }));

      await expectLater(
        backend.billingPortal(),
        throwsA(isA<BackendException>()
            .having((e) => e.problem, 'problem', BackendProblem.overLimit)),
      );
      backend.dispose();
    });

    test('the billing portal is a URL to open, never a card form in the app',
        () async {
      final backend = await _signedIn(MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(_tokenBody(), 200);
        }
        return http.Response(
            jsonEncode({'url': 'https://billing.test/session/abc'}), 200);
      }));

      expect((await backend.billingPortal(plan: 'pro')).toString(),
          'https://billing.test/session/abc');
      backend.dispose();
    });
  });

  group('scheduled tasks', () {
    test('reads the account\'s own tasks', () async {
      final backend = await _signedIn(MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(_tokenBody(), 200);
        }
        return http.Response(
            jsonEncode([
              {
                'id': 't1',
                'name': 'Morning brief',
                'cron': '0 8 * * *',
                'prompt': 'brief me',
                'enabled': true,
              }
            ]),
            200);
      }));

      final tasks = await backend.listScheduledTasks();
      expect(tasks.single.name, 'Morning brief');
      expect(tasks.single.cron, '0 8 * * *');
      backend.dispose();
    });

    test('saving stamps the owner, so the row cannot land under someone else',
        () async {
      final recorder = _Recorder();
      final backend = await _signedIn(recorder.client((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(_tokenBody(), 200);
        }
        return http.Response(
            jsonEncode([
              {
                'id': 't1',
                'name': 'Morning brief',
                'cron': '0 8 * * *',
                'prompt': 'brief me',
                'enabled': true,
              }
            ]),
            200);
      }));

      await backend.saveScheduledTask(const ScheduledTask(
          id: '', name: 'Morning brief', cron: '0 8 * * *', prompt: 'brief me'));

      final sent = jsonDecode(recorder.last.body) as Map<String, dynamic>;
      expect(sent['owner_id'], '11111111-1111-1111-1111-111111111111');
      expect(sent.containsKey('id'), isFalse,
          reason: 'a new task carries no id — the database assigns it');
      backend.dispose();
    });
  });

  test('the anon key rides on every request, because row security is what '
      'protects the data — not the secrecy of that key', () async {
    final recorder = _Recorder();
    final backend = await _signedIn(recorder.client((request) async {
      if (request.url.path.contains('/auth/')) {
        return http.Response(_tokenBody(), 200);
      }
      return http.Response(jsonEncode([]), 200);
    }));

    await backend.listProviderKeys();

    for (final request in recorder.requests) {
      expect(request.headers['apikey'], 'anon-key');
    }
    backend.dispose();
  });
}

/// Stands in for a real socket failure without importing `dart:io`, which the
/// web target cannot compile.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
  @override
  String toString() => 'SocketException: failed host lookup';
}
