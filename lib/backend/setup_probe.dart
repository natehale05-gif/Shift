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

  /// It *is* deployed, and the browser would not hand us its reply.
  ///
  /// Split out of [notDeployed] after the live project was asked directly:
  /// `provider-proxy` was ACTIVE the whole time this app was telling people to
  /// deploy it. The old code read every blocked reply as a missing function,
  /// because a missing function was the only cause it knew about — and so it
  /// sent the one person who could fix the real fault to change repository
  /// settings that were not the problem.
  replyBlocked,

  /// Deployed, and refusing this account: no membership, or over the ceiling.
  notEntitled,

  /// Deployed and reachable, but the server is not finished being set up.
  ///
  /// Three states share this, and they share it honestly — SHIFT holds no key
  /// for that provider, a required server setting is missing, or the
  /// entitlement check could not run. All three are the server's own to fix,
  /// none of them is the member's plan, and the server names which in its own
  /// words. It was called `noPlatformKey` while it described only the first.
  serverNotReady,

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

/// The stand-in status for "the function answered and the browser withheld it".
///
/// **Negative on purpose.** There is no HTTP status that means this, and the
/// alternative — threading a second axis through every caller and every fake —
/// buys nothing over one impossible number. Negative rather than an unassigned
/// 4xx so it cannot collide with something a provider genuinely sends: the
/// proxy forwards the upstream's status verbatim, and picking a real-looking
/// code would eventually mean reading a provider's answer as our own.
const int proxyReplyBlocked = -1;

/// Turns the proxy's HTTP answer into an outcome.
///
/// Pure, so every branch is testable without a network — which matters more
/// than usual here, because the thing being described is itself a diagnostic.
/// A diagnostic that is wrong is worse than none: it sends you to fix the
/// thing that was not broken.
ProxyProbeResult readProxyResponse(int status, String body) {
  final detail = _messageIn(body);

  return switch (status) {
    // Ours, never the wire's — see [proxyReplyBlocked].
    proxyReplyBlocked => ProxyProbeResult(
        ProxyOutcome.replyBlocked,
        'The proxy is deployed, but the browser blocked its reply, so this '
        'app never saw the answer. Try another browser, or turn off any '
        'content blocker for this site.',
        detail: detail,
      ),
    // The functions host answers 404 for a function that was never deployed.
    // Distinguishing this from "deployed but refusing" is the single most
    // useful thing this whole card does.
    404 => ProxyProbeResult(
        ProxyOutcome.notDeployed,
        'The proxy is not deployed on the server. Use the server settings '
        'below, then push any commit — from then on it deploys itself.',
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
    // 403 is the proxy's **own** refusal — a path its allowlist will not
    // forward — and it fell into the 4xx arm below, which reads every status
    // as the provider's. So the card blamed OpenAI for our routing, in the
    // same breath the chat card was blaming the member's key for it. Found by
    // the test that pins this against `sentenceForManagedStatus`.
    403 => ProxyProbeResult(
        ProxyOutcome.serverNotReady,
        detail ??
            'The server would not forward that call. Nothing is wrong with '
                'your account.',
        detail: detail,
      ),
    // The server's own words first, as 402 already does. 503 covers three
    // states — no key for this provider, a missing server setting, and an
    // entitlement check that could not run — and only the server knows which.
    // Overwriting its sentence with the commonest of the three would send
    // someone to paste a key they have already pasted.
    503 => ProxyProbeResult(
        ProxyOutcome.serverNotReady,
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

/// How the deployed proxy's route list compares to what this app needs.
enum RoutesOutcome {
  /// Every route the app asks for is one this server forwards.
  current,

  /// It answered, and does not forward something the app sends. The routes it
  /// is missing are named — this is the one state where being specific is the
  /// entire value, because "something is wrong with the server" is what the
  /// last week already said.
  behind,

  /// It does not know the question, which places it as older than the app
  /// asking. Not a failure — it is the answer.
  ///
  /// **Two statuses mean it, and for a while this only knew one.** A build
  /// predating the route rejects the request at whichever check it runs first:
  /// the one deployed to this project checks the method before it reads the
  /// path, so a GET comes back **405**, never reaching the provider table that
  /// would have said 404. The handler's own comment predicted 404 and the real
  /// server disproved it — so 405 lands here too, and the row that exists to
  /// spot a stale deploy stops reporting "unknown" against the stale deploy.
  older,

  /// Nothing answered, or the answer could not be read.
  unknown,
}

/// The comparison, and the sentence for it.
class RoutesReport {
  final RoutesOutcome outcome;
  final String message;

  /// `'openai POST /v1/images/generations'` — one line per route the server
  /// will not forward. Empty unless [outcome] is [RoutesOutcome.behind].
  final List<String> missing;

  /// The server's fingerprint of its own table, when it gave one. Useful only
  /// for telling two deploys apart in a report.
  final String? version;

  const RoutesReport(this.outcome, this.message,
      {this.missing = const [], this.version});
}

/// Compares what the app sends against what a running server says it forwards.
///
/// Pure, and it takes [required] as a parameter rather than importing it:
/// `tool/scan_backend_boundary.py` forbids `lib/backend/` importing the app,
/// and the required routes are the provider layer's own knowledge.
///
/// **This is the check that could not exist before.** The repo-level scan
/// compares the client to the allowlist *in this repository*, so it stayed
/// green for the week the deployed proxy was five commits behind with no image
/// route. Nothing compared the app to the server that was actually running.
RoutesReport readProxyRoutes(
  ({int status, String body})? answer, {
  required Map<String, List<String>> required,
}) {
  if (answer == null) {
    return const RoutesReport(RoutesOutcome.unknown,
        'Could not ask the server what it forwards. Check your connection.');
  }
  // 404 *or* 405 — see [RoutesOutcome.older]. Both are a build that predates
  // this route saying so, and which one you get depends only on the order of
  // the checks that build happens to run first.
  if (answer.status == 404 || answer.status == 405) {
    return const RoutesReport(
      RoutesOutcome.older,
      'This server is older than the app and cannot say what it forwards. '
      'Deploy the functions.',
    );
  }
  if (answer.status != 200) {
    return RoutesReport(RoutesOutcome.unknown,
        'The server would not say what it forwards (${answer.status}).');
  }

  final Map<String, dynamic> decoded;
  try {
    final parsed = jsonDecode(answer.body);
    if (parsed is! Map<String, dynamic>) throw const FormatException();
    decoded = parsed;
  } on FormatException {
    return const RoutesReport(RoutesOutcome.unknown,
        'The server answered something this app could not read.');
  }

  final version = decoded['version'];
  final allow = decoded['allow'];
  if (allow is! Map) {
    return const RoutesReport(RoutesOutcome.unknown,
        'The server answered something this app could not read.');
  }

  final missing = <String>[];
  for (final MapEntry(key: provider, value: routes) in required.entries) {
    final served = allow[provider];
    final permitted =
        served is List ? served.whereType<String>().toSet() : <String>{};
    for (final route in routes) {
      if (!permitted.contains(route)) missing.add('$provider $route');
    }
  }

  final build = version is String && version.isNotEmpty ? version : null;
  if (missing.isEmpty) {
    return RoutesReport(
      RoutesOutcome.current,
      'The server forwards everything this app asks for.',
      version: build,
    );
  }
  return RoutesReport(
    RoutesOutcome.behind,
    'The server will not forward ${missing.length == 1 ? missing.single : '${missing.length} of the routes this app uses'} '
    '— it is running an older build.',
    missing: missing,
    version: build,
  );
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
