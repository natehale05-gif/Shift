import 'dart:convert';

/// What a test call through the proxy actually told us.
///
/// This exists because the loop it replaces was "send a message and describe
/// what you saw" — which asks somebody on a phone to distinguish a 404 from a
/// 402 from a provider error, all of which look identical from the chat: a
/// reply that did not arrive.
///
/// Each outcome names the *one* thing to do next. That is the whole design
/// brief: a status code is not an instruction, and "something went wrong" is
/// not either.
enum ProxyOutcome {
  /// The function is not deployed. A 404 from the functions host.
  notDeployed,

  /// Deployed, and refusing this account: no membership, or over the ceiling.
  notEntitled,

  /// Deployed and entitled, but SHIFT holds no key for that provider.
  noPlatformKey,

  /// It reached the provider and the provider said no — a bad key, usually.
  providerRejected,

  /// Signed out, or the session expired.
  notSignedIn,

  /// Never got an answer: offline, DNS, a blocked network.
  unreachable,

  /// It worked.
  working,
}

/// An outcome plus the sentence to show for it.
class ProxyProbeResult {
  final ProxyOutcome outcome;

  /// Shown to the person who pressed the button.
  final String message;

  /// The provider's or server's own words, when there were any. Kept apart
  /// from [message] for the same reason `BackendException` keeps `detail`
  /// apart: one is for a person, the other is for working out why.
  final String? detail;

  const ProxyProbeResult(this.outcome, this.message, {this.detail});

  bool get isWorking => outcome == ProxyOutcome.working;
}

/// Turns the proxy's HTTP answer into an outcome.
///
/// Pure, so every branch is testable without a network — which matters more
/// than usual here, because the thing being described is itself a diagnostic.
/// A diagnostic that is wrong is worse than none: it sends you to fix the
/// thing that was not broken.
ProxyProbeResult readProxyResponse(int status, String body) {
  final detail = _messageIn(body);

  return switch (status) {
    // The functions host answers 404 for a function that was never deployed.
    // Distinguishing this from "deployed but refusing" is the single most
    // useful thing this whole card does.
    404 => ProxyProbeResult(
        ProxyOutcome.notDeployed,
        'The proxy is not deployed on the server. Add the two GitHub '
        'settings below and push any commit — from then on it deploys '
        'itself.',
        detail: detail,
      ),
    401 => ProxyProbeResult(
        ProxyOutcome.notSignedIn,
        'Your session expired. Sign out and back in.',
        detail: detail,
      ),
    402 || 429 => ProxyProbeResult(
        ProxyOutcome.notEntitled,
        detail ??
            'This account has no active plan, or has used everything its plan '
                'covers this month.',
        detail: detail,
      ),
    // The server's own words first, as 402 already does. 503 covers two
    // things — no key for this provider, and a server missing one of its own
    // settings — and only the server knows which. Overwriting its sentence
    // with the commoner of the two would send someone to paste a key they
    // have already pasted.
    503 => ProxyProbeResult(
        ProxyOutcome.noPlatformKey,
        detail ??
            'The server is running but holds no key for that provider. Add '
                'one under "Included with membership".',
        detail: detail,
      ),
    // The proxy forwards the provider's own status, so anything else in the
    // 4xx range came from the provider rather than from us.
    >= 400 && < 500 => ProxyProbeResult(
        ProxyOutcome.providerRejected,
        detail == null
            ? 'The provider rejected the call ($status). The stored key is the '
                'first thing to check.'
            : 'The provider rejected the call: $detail',
        detail: detail,
      ),
    >= 500 => ProxyProbeResult(
        ProxyOutcome.providerRejected,
        'The provider is having trouble right now ($status). Try again '
        'shortly.',
        detail: detail,
      ),
    _ => const ProxyProbeResult(
        ProxyOutcome.working,
        'Working — the call went through SHIFT\'s key and came back.',
      ),
  };
}

/// When no HTTP answer arrived at all.
const ProxyProbeResult proxyUnreachable = ProxyProbeResult(
  ProxyOutcome.unreachable,
  'Could not reach the server at all. Check your connection.',
);

/// When the app has no backend compiled in, or nobody is signed in — asked
/// before a request is made, so the button does not spend a round trip
/// confirming something already known.
const ProxyProbeResult proxyNotSignedIn = ProxyProbeResult(
  ProxyOutcome.notSignedIn,
  'Sign in first — the test runs as your account.',
);

/// The sentence a server buried in its error body, if it left one.
String? _messageIn(String body) {
  if (body.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return null;
    final error = decoded['error'];
    final candidate = error is Map
        ? (error['message'] ?? error['detail'])
        : (decoded['message'] ?? decoded['msg'] ?? error);
    if (candidate is! String || candidate.trim().isEmpty) return null;
    final text = candidate.trim();
    return text.length > 240 ? '${text.substring(0, 237)}…' : text;
  } on FormatException {
    return null;
  }
}
