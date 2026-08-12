import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shift/backend/setup_probe.dart';
import 'package:shift/providers/clients/anthropic_text.dart';
import 'package:shift/providers/clients/openai_image.dart';
import 'package:shift/providers/clients/openai_text.dart';
import 'package:shift/providers/proxy_routes.dart';

/// Whether the server that is *running* forwards what this app sends.
///
/// The check that could not exist before. Everything else compares the client
/// to the allowlist in this repository, which stayed green for a week while the
/// deployed proxy was five commits behind — no image route at all — and the
/// only symptom was a member's failed turn, reported to them as a rejected key.
void main() {
  /// The live server on 3 August, which is what the phone has been talking to.
  String olderServer() => jsonEncode({
        'version': 'deadbeef',
        'allow': {
          'anthropic': ['POST /v1/messages'],
          'openai': ['POST /v1/chat/completions', 'POST /v1/responses'],
          'gemini': ['POST /v1beta/models/'],
          'groq': ['POST /v1/chat/completions'],
          'mistral': ['POST /v1/chat/completions'],
          'openrouter': ['POST /v1/chat/completions'],
        },
      });

  String currentServer() => jsonEncode({
        'version': 'cafebabe',
        'allow': {
          for (final MapEntry(key: id, value: routes)
              in requiredProxyRoutes.entries)
            id: routes,
        },
      });

  group('what the app requires', () {
    test('covers every managed path its clients build', () {
      // The mirror, pinned in the suite as well as in the scan — CI runs the
      // scan, but a change made without running it should still go red here.
      expect(requiredProxyRoutes['anthropic'],
          contains('POST ${AnthropicText.providerPath}'));
      expect(requiredProxyRoutes['openai'],
          contains('POST ${OpenAiText.providerPath}'));
      expect(requiredProxyRoutes['openai'],
          contains('POST ${OpenAiImage.providerPath}'));

      // `openai_text` serves four providers, so one route has to be claimed
      // for each of them — this is the shape that broke four at once.
      for (final id in ['groq', 'mistral', 'openrouter']) {
        expect(requiredProxyRoutes[id],
            contains('POST ${OpenAiText.providerPath}'),
            reason: id);
      }
    });
  });

  group('reading what the server said', () {
    test('the reported failure, named as the route it is', () {
      // The exact state the phone has been in. Not "something is wrong with
      // the server" — that is what a week of failed turns already said.
      final report = readProxyRoutes(
        (status: 200, body: olderServer()),
        required: requiredProxyRoutes,
      );

      expect(report.outcome, RoutesOutcome.behind);
      expect(report.missing, ['openai POST /v1/images/generations']);
      expect(report.message, contains('POST /v1/images/generations'));
      expect(report.version, 'deadbeef');
    });

    test('a server that forwards everything says so', () {
      final report = readProxyRoutes(
        (status: 200, body: currentServer()),
        required: requiredProxyRoutes,
      );

      expect(report.outcome, RoutesOutcome.current);
      expect(report.missing, isEmpty);
      expect(report.version, 'cafebabe');
    });

    test('a 404 is the finding, not an error', () {
      // `_shift` is not a provider, so a proxy built before this route existed
      // answers 404 — which places it as older than the app asking. Reporting
      // that as "could not reach the server" would be the same mistake this
      // whole card exists to stop.
      final report = readProxyRoutes((status: 404, body: ''),
          required: requiredProxyRoutes);

      expect(report.outcome, RoutesOutcome.older);
      expect(report.message, contains('older'));
      expect(report.message, isNot(contains('connection')));
    });

    test('nothing answering is a different state again', () {
      expect(readProxyRoutes(null, required: requiredProxyRoutes).outcome,
          RoutesOutcome.unknown);
    });

    test('an unreadable answer is never read as current', () {
      // The direction that matters: a body we cannot parse must not become a
      // report that everything is fine.
      for (final body in ['', 'not json', '{"allow":"nope"}', '[]']) {
        expect(
          readProxyRoutes((status: 200, body: body),
              required: requiredProxyRoutes).outcome,
          RoutesOutcome.unknown,
          reason: body,
        );
      }
    });

    test('a provider missing entirely is missing, not skipped', () {
      // An absent key and an empty list are the same answer — it will not
      // forward that — and neither may be quietly treated as satisfied.
      final report = readProxyRoutes(
        (status: 200, body: jsonEncode({'version': 'x', 'allow': <String, dynamic>{}})),
        required: const {'openai': ['POST /v1/chat/completions']},
      );

      expect(report.outcome, RoutesOutcome.behind);
      expect(report.missing, ['openai POST /v1/chat/completions']);
    });

    test('several missing routes are counted, and all of them listed', () {
      final report = readProxyRoutes(
        (status: 200, body: jsonEncode({'allow': <String, dynamic>{}})),
        required: const {
          'openai': ['POST /v1/chat/completions', 'POST /v1/images/generations'],
        },
      );

      expect(report.missing.length, 2);
      expect(report.message, contains('2 of the routes'));
      // No version claimed when the server did not give one — a build stamp
      // invented here would be worse than none.
      expect(report.version, isNull);
    });
  });
}
