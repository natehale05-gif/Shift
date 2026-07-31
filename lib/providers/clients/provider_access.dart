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
