/// How a provider call is paid for and authorised.
///
/// Two ways, and the difference is where the secret lives:
///
/// [DirectKey] — the member's own key, kept on this device, sent to the
/// provider by this device. The arrangement the app shipped with, and the one
/// that keeps working with no account.
///
/// [ManagedAccess] — SHIFT's key, held on the server. The device sends the
/// same request to SHIFT's proxy with its *session* token, and the provider
/// credential is attached out of reach. The member's device never holds it,
/// never sees it, and cannot ask for it — which is the only version of
/// "included with your membership" worth offering.
///
/// A sealed type rather than a nullable key so the analyser names every place
/// that has to decide, instead of an empty string quietly meaning "managed"
/// somewhere down the stack.
sealed class ProviderAccess {
  const ProviderAccess();
}

/// A key this device holds.
final class DirectKey extends ProviderAccess {
  final String key;

  const DirectKey(this.key);
}

/// A call SHIFT makes on the member's behalf.
///
/// [base] already names the provider — `…/functions/v1/provider-proxy/gemini`
/// — and each client appends the path it would have used anyway, so provider
/// URL knowledge stays in the client that owns it and the server stays a
/// forwarder rather than a second implementation of three wire protocols.
final class ManagedAccess extends ProviderAccess {
  final Uri base;

  /// What identifies the member to SHIFT. Never a provider credential.
  final Map<String, String> headers;

  const ManagedAccess({required this.base, required this.headers});

  /// The proxy URL for a provider path such as `/v1/messages`.
  Uri resolve(String path, {Map<String, String> query = const {}}) {
    final trimmed = path.startsWith('/') ? path : '/$path';
    return base.replace(
      path: '${base.path}$trimmed',
      queryParameters: query.isEmpty ? null : query,
    );
  }
}

/// Where one call goes and what it carries, whichever way it is being paid for.
///
/// Every client had grown its own `switch (access)` — three lines of URI and
/// three of headers, repeated. That was tolerable while only the text clients
/// took managed access; once video, speech and images did too it became six
/// copies of a decision that has exactly one right answer, which is how one of
/// them ends up subtly different.
///
/// [direct] and [directHeaders] are the provider's own scheme, given the key:
/// HeyGen puts it in `x-api-key`, ElevenLabs in `xi-api-key`, Gemini in the
/// URL. The managed branch needs none of that — the proxy attaches the
/// credential — so it takes the path and the session headers and nothing else.
({Uri uri, Map<String, String> headers}) routeCall(
  ProviderAccess access, {
  required Uri Function(String key) direct,
  required Map<String, String> Function(String key) directHeaders,
  required String path,
  Map<String, String> query = const {},
}) =>
    switch (access) {
      DirectKey(:final key) => (
          uri: direct(key),
          headers: directHeaders(key),
        ),
      ManagedAccess(:final base, headers: final auth) => (
          uri: ManagedAccess(base: base, headers: const {})
              .resolve(path, query: query),
          // `content-type` is the only one the browser sends without asking
          // permission first. Anything the provider additionally wants is the
          // proxy's to add — a header the proxy has not allowed is a request
          // blocked before it leaves the device.
          headers: {'content-type': 'application/json', ...auth},
        ),
    };
