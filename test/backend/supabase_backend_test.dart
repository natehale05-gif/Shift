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

  /// The first request whose path ends with [suffix]. Named rather than
  /// positional because sign-in now makes more than one call, and asserting on
  /// "the last request" would silently start testing a different one every
  /// time a step is added.
  http.Request to(String suffix) =>
      requests.firstWhere((r) => r.url.path.endsWith(suffix));
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
      expect(recorder.to('/token').url.queryParameters['grant_type'],
          'password');
      backend.dispose();
    });

    test('provisions the account its profile row, which nothing else creates',
        () async {
      // Not a trigger: the schema deliberately never names the auth tables, so
      // that the identity provider stays replaceable. Without this call an
      // account signs up successfully and has no profile — and `is_admin` has
      // no row to live in.
      final recorder = _Recorder();
      final backend = _backend(
          recorder.client((_) async => http.Response(_tokenBody(), 200)));

      await backend.signIn(email: 'a@test', password: 'pw');

      final profile = recorder.to('/profiles');
      expect(profile.method, 'POST');
      expect(profile.headers['Prefer'], contains('ignore-duplicates'));
      expect(profile.body, contains('11111111-1111-1111-1111-111111111111'));
      // Never sent, because the column grant would refuse it anyway — but a
      // client that tried would be a client that believed it could.
      expect(profile.body, isNot(contains('is_admin')));
      backend.dispose();
    });

    test('a profile that cannot be written does not fail the sign-in',
        () async {
      // Someone who typed the right password is signed in. A bookkeeping row
      // is not their problem, and the next sign-in tries again.
      final backend = _backend(MockClient((request) async {
        if (request.url.path.endsWith('/profiles')) {
          return http.Response('{"message":"nope"}', 500);
        }
        return http.Response(_tokenBody(), 200);
      }));

      final session = await backend.signIn(email: 'a@test', password: 'pw');
      expect(session.accessToken, 'access-1');
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

    test('a network failure is reported as a sentence, never as the raw '
        'exception', () async {
      // Caught by running it: this displayed
      //   ClientException: Failed to fetch, uri=https://<project>.supabase.co
      //     /auth/v1/token?grant_type=password
      // inside the sign-in form — meaningless to the person who typed a
      // password, and it prints the project's address on screen. The detail
      // belongs in the log, not in the message.
      final backend = _backend(MockClient((_) async {
        throw const SocketExceptionStub();
      }));

      try {
        await backend.signIn(email: 'a@test', password: 'pw');
        fail('should have thrown');
      } on BackendException catch (e) {
        expect(e.message, isNot(contains('Exception')));
        expect(e.message, isNot(contains('http')));
        expect(e.message, isNot(contains('uri=')));
        expect(e.message, contains('Could not reach the server'));
        expect(e.detail, isNotNull,
            reason: 'the cause is kept, just not shown');
      }
      backend.dispose();
    });

    test('a server error with no body still says something actionable',
        () async {
      // A bare "Something went wrong (503)" tells the user nothing to do.
      final backend = _backend(MockClient((_) async => http.Response('', 503)));

      try {
        await backend.signIn(email: 'a@test', password: 'pw');
        fail('should have thrown');
      } on BackendException catch (e) {
        expect(e.problem, BackendProblem.unavailable);
        expect(e.message, contains('try again'));
        expect(e.message, isNot(contains('503')));
        expect(e.detail, contains('503'));
      }
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
            .having((e) => e.message, 'message', contains('confirm'))
            // Its own problem, not `credentials`: the account was created, and
            // the UI shows it as a notice rather than in red under a form that
            // just did what it was asked.
            .having((e) => e.problem, 'problem',
                BackendProblem.confirmationRequired)),
      );
      backend.dispose();
    });
  });

  group('admin', () {
    test('is read from the server, never from the token', () async {
      final recorder = _Recorder();
      final backend = _backend(
        recorder.client((request) async =>
            request.url.path.endsWith('/profiles')
                ? http.Response('[{"is_admin":true}]', 200)
                : http.Response(_tokenBody(), 200)),
      );
      await backend.signIn(email: 'a@test', password: 'pw');

      expect(await backend.isAdmin(), isTrue);
      expect(
        recorder.requests.any((r) =>
            r.method == 'GET' && r.url.query.contains('select=is_admin')),
        isTrue,
      );
      backend.dispose();
    });

    test('a profile with no row, or a request that fails, is not an admin',
        () async {
      final empty = _backend(MockClient((request) async =>
          request.url.path.endsWith('/profiles')
              ? http.Response('[]', 200)
              : http.Response(_tokenBody(), 200)));
      await empty.signIn(email: 'a@test', password: 'pw');
      expect(await empty.isAdmin(), isFalse);
      empty.dispose();

      // The important half: a network failure must not read as a promotion.
      final broken = _backend(MockClient((request) async =>
          request.url.path.endsWith('/profiles') && request.method == 'GET'
              ? throw Exception('offline')
              : http.Response(_tokenBody(), 200)));
      await broken.signIn(email: 'a@test', password: 'pw');
      expect(await broken.isAdmin(), isFalse);
      broken.dispose();
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

  group('a function that is not there', () {
    // The bug this group exists for: tapping Grant against a function that had
    // never been deployed answered "check your connection", because a browser
    // cannot see the functions host's 404 — that 404 carries no CORS header,
    // so the request just fails. The fix is one extra question, and these
    // tests pin both of its answers.

    /// A world where the functions host refuses and everything else answers.
    MockClient client({required bool hostUp}) => MockClient((request) async {
          if (request.url.path.contains('/auth/')) {
            return http.Response(_tokenBody(), 200);
          }
          if (request.url.path.contains('/functions/')) {
            throw const SocketExceptionStub();
          }
          if (!hostUp) throw const SocketExceptionStub();
          return http.Response(jsonEncode([]), 200);
        });

    test('is named, when the host itself is answering', () async {
      final backend = await _signedIn(client(hostUp: true));

      await expectLater(
        backend.grantMembership(ceilingMicros: 25000000),
        throwsA(isA<BackendException>()
            .having((e) => e.problem, 'problem', BackendProblem.notDeployed)
            .having((e) => e.message, 'message', contains('admin-membership'))),
      );
      backend.dispose();
    });

    test('is still just "offline" when nothing answers at all', () async {
      // The regression guard, and the more important half. A diagnostic that
      // upgrades every outage into "not deployed" would send someone to
      // redeploy a server that was never broken.
      final backend = await _signedIn(client(hostUp: false));

      await expectLater(
        backend.grantMembership(ceilingMicros: 25000000),
        throwsA(isA<BackendException>()
            .having((e) => e.problem, 'problem', BackendProblem.unavailable)),
      );
      backend.dispose();
    });

    test('a 4xx from a deployed function is reported as itself', () async {
      // The other regression: the extra question must only be asked when there
      // was no answer. A function that replied 403 has plainly been deployed.
      final backend = await _signedIn(MockClient((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(_tokenBody(), 200);
        }
        return http.Response('{"message":"Not allowed."}', 403);
      }));

      await expectLater(
        backend.grantMembership(ceilingMicros: 25000000),
        throwsA(isA<BackendException>()
            .having((e) => e.problem, 'problem', BackendProblem.notSignedIn)
            .having((e) => e.message, 'message', 'Not allowed.')),
      );
      backend.dispose();
    });

    test('the probe sends what a real turn sends', () async {
      // The probe reported the proxy working while every turn failed, because
      // it sent fewer headers than the client does: no `anthropic-version`, so
      // a different — and easier — CORS preflight. A test call that asks a
      // smaller question than the product is not a test, it is a reassurance.
      final recorder = _Recorder();
      final backend = await _signedIn(recorder.client((request) async {
        if (request.url.path.contains('/auth/')) {
          return http.Response(_tokenBody(), 200);
        }
        return http.Response('{}', 200);
      }));

      await backend.probeProxy('anthropic',
          extraHeaders: const {'anthropic-version': '2023-06-01'});

      final probe = recorder.to('/v1/messages');
      expect(probe.headers['anthropic-version'], '2023-06-01');
      expect(probe.headers['Authorization'], isNotNull,
          reason: 'our own headers must survive the merge');
      backend.dispose();
    });

    test('the proxy probe reports the 404 the browser withheld', () async {
      // Synthesised rather than given a seventh outcome, so there stays
      // exactly one place that turns a proxy status into a sentence.
      final backend = await _signedIn(client(hostUp: true));

      expect(await backend.probeProxy('anthropic'), (status: 404, body: ''));
      backend.dispose();
    });

    test('the proxy probe reports nothing when nothing answers', () async {
      final backend = await _signedIn(client(hostUp: false));

      expect(await backend.probeProxy('anthropic'), isNull);
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
