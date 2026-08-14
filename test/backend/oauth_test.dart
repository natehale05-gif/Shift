import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shift/backend/backend_config.dart';
import 'package:shift/backend/no_backend.dart';
import 'package:shift/backend/shift_backend.dart';
import 'package:shift/backend/supabase_backend.dart';

/// Signing in with Apple or Google.
///
/// The round trip cannot be exercised here — it leaves the app, and
/// `*.supabase.co` is unreachable from this sandbox anyway — so what is pinned
/// is the two ends: the URL the browser is sent to, and what is made of the URL
/// it comes back on. Everything between those is the provider's.
void main() {
  const config = BackendConfig(
    url: 'https://project.test',
    anonKey: 'anon-key',
  );

  SupabaseBackend backend() => SupabaseBackend(config: config);

  /// A JWT with [sub] in its payload. Unsigned, because nothing here verifies
  /// it — the server does, on every call.
  String tokenFor(String sub) {
    String seg(Object json) =>
        base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    return '${seg({'alg': 'none'})}.${seg({'sub': sub})}.signature';
  }

  group('where the browser is sent', () {
    test('names the provider and where to come back to', () {
      final url = backend().oauthUrl(
        OAuthProvider.google,
        redirectTo: Uri.parse('https://app.test/Shift/'),
      )!;

      expect(url.host, 'project.test');
      expect(url.path, '/auth/v1/authorize');
      expect(url.queryParameters['provider'], 'google');
      expect(url.queryParameters['redirect_to'], 'https://app.test/Shift/');
    });

    test('Apple is offered too, and that is not optional', () {
      // App Store 4.8: an app offering a third-party login must offer one that
      // limits collection to name and email. Shipping Google alone is a
      // rejection, so the enum having exactly these two members is the rule.
      expect(OAuthProvider.values.map((p) => p.id), ['apple', 'google']);
      expect(
        backend()
            .oauthUrl(OAuthProvider.apple,
                redirectTo: Uri.parse('https://app.test/'))!
            .queryParameters['provider'],
        'apple',
      );
    });

    test('a build with no server has nowhere to send anyone', () {
      expect(
        NoBackend()
            .oauthUrl(OAuthProvider.google, redirectTo: Uri.parse('https://a/')),
        isNull,
      );
    });
  });

  group('which providers the host has', () {
    /// A backend whose only HTTP is the settings call these tests are about.
    SupabaseBackend answering(http.Response Function(http.Request) reply) =>
        SupabaseBackend(config: config, client: MockClient((r) async => reply(r)));

    String settings(Map<String, dynamic> external) =>
        jsonEncode({'external': external});

    test('asks the host, and takes it at its word', () async {
      late Uri asked;
      final backend = answering((r) {
        asked = r.url;
        return http.Response(
            settings({'apple': false, 'google': true, 'github': true}), 200);
      });

      expect(await backend.enabledProviders(), {OAuthProvider.google});
      expect(asked.path, '/auth/v1/settings');
    });

    test('none enabled is an answer, and it means no buttons', () async {
      // The state that produced the report: both providers off, and the app
      // sent someone to a page that could only say so in JSON.
      final backend =
          answering((_) => http.Response(settings({'apple': false, 'google': false}), 200));

      expect(await backend.enabledProviders(), isEmpty);
    });

    // The three ways of not finding out. All three answer with everything,
    // which is the rule the interface states: hiding a working sign-in on one
    // failed request is worse than the rare bad redirect.
    test('a refused request hides nothing', () async {
      final backend = answering((_) => http.Response('nope', 500));
      expect(await backend.enabledProviders(), OAuthProvider.values.toSet());
    });

    test('a body with no `external` hides nothing', () async {
      final backend = answering((_) => http.Response('{"disable_signup":false}', 200));
      expect(await backend.enabledProviders(), OAuthProvider.values.toSet());
    });

    test('a request that never lands hides nothing', () async {
      final backend = SupabaseBackend(
        config: config,
        client: MockClient(
            (_) async => throw http.ClientException('Failed to fetch')),
      );
      expect(await backend.enabledProviders(), OAuthProvider.values.toSet());
    });

    test('a build with no server has nothing configured on one', () async {
      // Empty here is the truth rather than a failure to ask, which is why
      // this one arm is allowed to answer with nothing.
      expect(await NoBackend().enabledProviders(), isEmpty);
    });
  });

  group('coming back', () {
    test('an ordinary load carries no session and is not an error', () async {
      // This runs on every boot. A throw here would make opening the app an
      // exception path.
      expect(await backend().adoptCallback(Uri.parse('https://app.test/Shift/')),
          isNull);
    });

    test('a fragment with tokens becomes a session', () async {
      final session = await backend().adoptCallback(Uri.parse(
        'https://app.test/Shift/#access_token=${tokenFor('user-1')}'
        '&refresh_token=r1&expires_in=3600&token_type=bearer',
      ));

      expect(session, isNotNull);
      expect(session!.account.id, 'user-1',
          reason: 'read from the token itself, not from a second request');
      expect(session.refreshToken, 'r1');
      expect(session.isExpired, isFalse);
    });

    test('cancelling says so rather than looking like nothing happened',
        () async {
      // The button navigated away and came back. Answering null would be
      // indistinguishable from an ordinary load, and the app would appear to
      // have ignored the tap.
      await expectLater(
        backend().adoptCallback(Uri.parse(
            'https://app.test/#error=access_denied&error_description=User+cancelled')),
        throwsA(isA<BackendException>().having(
          (e) => e.message,
          'message',
          contains('cancelled'),
        )),
      );
    });

    test('any other refusal is reported as one, not as a cancellation',
        () async {
      await expectLater(
        backend()
            .adoptCallback(Uri.parse('https://app.test/#error=server_error')),
        throwsA(isA<BackendException>().having(
          (e) => e.message,
          'message',
          contains('did not complete'),
        )),
      );
    });

    test('a fragment with no token is nothing, not a broken session', () async {
      // Anchors exist. `#settings` is not a sign-in.
      expect(await backend().adoptCallback(Uri.parse('https://app.test/#top')),
          isNull);
    });

    test('a token that is not a JWT yields no session', () async {
      // Rather than a session whose account id is empty, which would look
      // signed in and fail on every call it made.
      expect(
        await backend().adoptCallback(
            Uri.parse('https://app.test/#access_token=not-a-jwt&expires_in=60')),
        isNull,
      );
    });

    test('the expiry comes from the callback, not from a guess', () async {
      final session = await backend().adoptCallback(Uri.parse(
        'https://app.test/#access_token=${tokenFor('u')}&expires_in=60',
      ));

      // `isExpired` treats a token as dead a minute early, so a 60-second one
      // is already expired on arrival — which is the honest reading and the
      // reason the refresh token travels with it.
      expect(session!.isExpired, isTrue);
    });
  });
}
