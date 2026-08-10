import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'access.dart';
import 'clients/anthropic_text.dart';
import 'failure_text.dart';
import 'registry.dart';
import 'streaming/reachability.dart';
import 'streaming/sse_client.dart';

/// What one real request to a provider actually did.
///
/// The point of naming these separately is that they have **different owners**.
/// A rejected key is the user's to fix; a blocked request is their browser's;
/// a rate limit is nobody's and resolves by waiting. One sentence covering all
/// three sends people to check the thing that was never wrong — which is the
/// failure this whole wave exists to remove.
enum ProbeOutcome {
  working,
  keyRejected,
  modelUnavailable,
  outOfCredit,
  rateLimited,
  providerProblem,

  /// The request never left the device: refused by the browser, a content
  /// blocker, or a response with no CORS headers to read.
  blocked,

  /// Nothing is reachable at all.
  offline,

  /// Accepted, then never answered.
  timedOut,

  /// It failed, and we cannot say more honestly than that. Off-web there is no
  /// browser to blame, so [blocked] would be a guess.
  unreachable,
}

/// Decides the outcome from what came back. Pure, so every sentence below is
/// testable with no network — which matters because most of them cannot be
/// reproduced in this sandbox at all.
///
/// [status] is null when no HTTP status ever arrived, which is the case the
/// [reach] answer exists to disambiguate.
ProbeOutcome probeOutcome({required int? status, required Reach reach}) {
  if (status == null) {
    return switch (reach) {
      Reach.down => ProbeOutcome.offline,
      Reach.up => ProbeOutcome.blocked,
      Reach.unknown => ProbeOutcome.unreachable,
    };
  }
  if (status >= 200 && status < 300) return ProbeOutcome.working;
  return switch (status) {
    401 || 403 => ProbeOutcome.keyRejected,
    402 => ProbeOutcome.outOfCredit,
    404 => ProbeOutcome.modelUnavailable,
    429 => ProbeOutcome.rateLimited,
    _ => ProbeOutcome.providerProblem,
  };
}

/// One sentence per outcome, and no two alike — asserted by a test, because
/// two states sharing a sentence is exactly the defect this replaces.
String probeSentence(ProbeOutcome outcome) => switch (outcome) {
      ProbeOutcome.working => 'Working. That key answered.',
      ProbeOutcome.keyRejected => sentenceForStatus(401),
      ProbeOutcome.modelUnavailable => sentenceForStatus(404),
      ProbeOutcome.outOfCredit => sentenceForStatus(402),
      ProbeOutcome.rateLimited => sentenceForStatus(429),
      ProbeOutcome.providerProblem => sentenceForStatus(500),
      ProbeOutcome.blocked => sentenceForUnreachable(Reach.up),
      ProbeOutcome.offline => sentenceForUnreachable(Reach.down),
      ProbeOutcome.timedOut => sentenceForTimeout,
      ProbeOutcome.unreachable => sentenceForUnreachable(Reach.unknown),
    };

/// The smallest real request that proves a key works, per provider.
///
/// Deliberately the **same host and the same headers** the client uses. A test
/// that asked a different URL would answer a different question — including
/// about CORS, which is per-origin and per-header and is the thing most likely
/// to be at fault.
///
/// Null for a provider with no wire client yet: offering to test something that
/// cannot run is the kind of button that erodes trust in every other one.
({Uri uri, Map<String, String> headers, String body})? probeRequest(
  String providerId,
  ProviderAccess access,
) {
  switch (providerId) {
    case 'anthropic':
      final target = AnthropicText.target(access);
      return (
        uri: target.uri,
        headers: target.headers,
        // One token, no thinking, no streaming. It costs a fraction of a cent
        // and it is a genuine authenticated generation — a metadata endpoint
        // would pass with a key that cannot actually be spent.
        body: jsonEncode(AnthropicText.buildBody(
          model: 'claude-haiku-4-5',
          instruction: 'hi',
          maxTokens: 1,
          thinking: false,
        )
          ..remove('stream')),
      );
    default:
      return null;
  }
}

/// Whether Settings should offer a connection test for this provider.
bool canProbe(ProviderDescriptor provider) =>
    probeRequest(provider.id, const DirectKey('probe')) != null;

/// Sends the request and reports which state it hit.
Future<ProbeOutcome> runProbe({
  required String providerId,
  required ProviderAccess access,
  http.Client Function()? clientFactory,
  Future<Reach> Function()? reach,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final request = probeRequest(providerId, access);
  if (request == null) return ProbeOutcome.providerProblem;

  final client = (clientFactory ?? createProviderHttpClient)();
  try {
    final response = await client
        .post(request.uri, headers: request.headers, body: request.body)
        .timeout(timeout);
    return probeOutcome(status: response.statusCode, reach: Reach.unknown);
  } on TimeoutException {
    // Accepted and then silent. Not the same as refused, and not worth asking
    // the reachability probe about: something clearly got through.
    return ProbeOutcome.timedOut;
  } catch (_) {
    // No status. Which of the three this is, is exactly what the reachability
    // probe answers — and it is only asked here, after something failed.
    return probeOutcome(status: null, reach: await (reach ?? probeReach)());
  } finally {
    client.close();
  }
}
