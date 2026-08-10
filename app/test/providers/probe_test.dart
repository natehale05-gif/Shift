import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shift/providers/access.dart';
import 'package:shift/providers/clients/anthropic_text.dart';
import 'package:shift/providers/probe.dart';
import 'package:shift/providers/registry.dart';
import 'package:shift/providers/streaming/reachability.dart';

/// The connection test in Settings — the control that replaces a round trip of
/// "describe what you saw" with a sentence naming the state.
void main() {
  group('deciding the outcome', () {
    test('a 2xx is working', () {
      expect(probeOutcome(status: 200, reach: Reach.unknown),
          ProbeOutcome.working);
    });

    test('each failing status maps to its own owner', () {
      // The reason these are separate at all: a rejected key is the user's to
      // fix, a rate limit resolves by waiting, and a 500 is nobody's.
      expect(probeOutcome(status: 401, reach: Reach.unknown),
          ProbeOutcome.keyRejected);
      expect(probeOutcome(status: 402, reach: Reach.unknown),
          ProbeOutcome.outOfCredit);
      expect(probeOutcome(status: 404, reach: Reach.unknown),
          ProbeOutcome.modelUnavailable);
      expect(probeOutcome(status: 429, reach: Reach.unknown),
          ProbeOutcome.rateLimited);
      expect(probeOutcome(status: 503, reach: Reach.unknown),
          ProbeOutcome.providerProblem);
    });

    test('no status at all is decided by reachability', () {
      expect(probeOutcome(status: null, reach: Reach.down),
          ProbeOutcome.offline);
      expect(probeOutcome(status: null, reach: Reach.up),
          ProbeOutcome.blocked);
      expect(probeOutcome(status: null, reach: Reach.unknown),
          ProbeOutcome.unreachable);
    });
  });

  test('no two outcomes share a sentence', () {
    // The whole failure being removed, in one assertion: states that read the
    // same are states nobody can act on differently.
    final said = {for (final o in ProbeOutcome.values) probeSentence(o)};
    expect(said, hasLength(ProbeOutcome.values.length));
  });

  group('the request it sends', () {
    test('is the same host and headers the client uses', () {
      // A test that asked a different URL would answer a different question —
      // including about CORS, which is per-origin and per-header and is the
      // thing most likely to be at fault.
      const access = DirectKey('sk-ant-x');
      final request = probeRequest('anthropic', access)!;
      final real = AnthropicText.target(access);

      expect(request.uri, real.uri);
      expect(request.headers, real.headers);
    });

    test('is as small as a real generation can be', () {
      final body = jsonDecode(probeRequest('anthropic', const DirectKey('k'))!
          .body) as Map<String, dynamic>;

      expect(body['max_tokens'], 1);
      expect(body.containsKey('thinking'), isFalse);
      expect(body.containsKey('stream'), isFalse,
          reason: 'the probe reads one status; streaming it would be theatre');
    });

    test('is null for a provider with no client yet', () {
      // Offering to test something that cannot run is the kind of button that
      // erodes trust in every other one.
      expect(probeRequest('groq', const DirectKey('k')), isNull);
      expect(canProbe(kProviders.firstWhere((p) => p.id == 'groq')), isFalse);
      expect(
          canProbe(kProviders.firstWhere((p) => p.id == 'anthropic')), isTrue);
    });
  });

  group('running it', () {
    Future<ProbeOutcome> against(
      Future<http.Response> Function() respond, {
      Reach reach = Reach.unknown,
    }) =>
        runProbe(
          providerId: 'anthropic',
          access: const DirectKey('sk-ant-x'),
          clientFactory: () => _FakeClient(respond),
          reach: () async => reach,
          timeout: const Duration(milliseconds: 200),
        );

    test('a 200 is working', () async {
      expect(await against(() async => http.Response('{}', 200)),
          ProbeOutcome.working);
    });

    test('a 401 names the key', () async {
      expect(await against(() async => http.Response('{}', 401)),
          ProbeOutcome.keyRejected);
    });

    test('a refused request with the origin up is reported as blocked',
        () async {
      expect(
        await against(
          () async => throw http.ClientException('Failed to fetch'),
          reach: Reach.up,
        ),
        ProbeOutcome.blocked,
      );
    });

    test('a refused request with nothing reachable is reported as offline',
        () async {
      expect(
        await against(
          () async => throw http.ClientException('Failed to fetch'),
          reach: Reach.down,
        ),
        ProbeOutcome.offline,
      );
    });

    test('a stall is a timeout, not a block', () async {
      expect(
        await against(
          () async {
            await Future<void>.delayed(const Duration(seconds: 5));
            return http.Response('{}', 200);
          },
          // Forced to `up`, so a missing timeout arm would show as `blocked`
          // rather than passing quietly.
          reach: Reach.up,
        ),
        ProbeOutcome.timedOut,
      );
    });
  });
}

class _FakeClient extends http.BaseClient {
  final Future<http.Response> Function() respond;

  _FakeClient(this.respond);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await respond();
    return http.StreamedResponse(
      Stream.value(utf8.encode(response.body)),
      response.statusCode,
    );
  }
}
