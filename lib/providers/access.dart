/// How a call to a provider is paid for and authorised.
///
/// Sealed, because the two arms are not variations on a theme — they differ in
/// *where the secret lives*, which is the whole security argument for the
/// subscription. A [DirectKey] call carries the user's own credential from
/// their device; a [ManagedAccess] call carries a session token to SHIFT's
/// proxy, which injects the real key server-side and never returns it. A
/// client that took a nullable `apiKey` could not express the second at all,
/// which is how v1 ended up with a special case per call site.
sealed class ProviderAccess {
  const ProviderAccess();
}

/// The user's own key, held on their device, sent straight to the provider.
///
/// Works with no account and no server, which is what keeps the app usable for
/// someone who never signs in — and what makes it verifiable end to end the
/// moment there is a key.
class DirectKey extends ProviderAccess {
  final String key;

  const DirectKey(this.key);
}

/// SHIFT's key, spent through the metered proxy on the user's behalf.
///
/// [base] is the proxy, not the provider: the request path and body are the
/// provider's, so the wire clients do not need to know which arm they got.
/// That is deliberate — it is what stops the server becoming a second
/// implementation of three streaming protocols it would then have to track.
///
/// [headers] carries a session token with a short life, so it is fetched per
/// call rather than cached on the client.
class ManagedAccess extends ProviderAccess {
  final Uri base;
  final Map<String, String> headers;

  const ManagedAccess({required this.base, required this.headers});
}

/// What an account is entitled to spend from SHIFT's keys.
class Entitlement {
  /// Whether a plan is active *and* under its ceiling. One flag rather than
  /// two, because every caller wants the conjunction and asking them to
  /// remember both is how one of them forgets.
  final bool canSpendManaged;

  /// Providers this plan covers. A plan that covers text but not video is an
  /// ordinary shape, not an edge case.
  final Set<String> includedProviders;

  /// Whether the plan is *active but spent*, as opposed to absent.
  ///
  /// Carried separately because the two produce the same `canSpendManaged` and
  /// need opposite sentences: "start a plan" is wrong advice for somebody who
  /// has one and has used it up.
  final bool overCeiling;

  /// False when the server could not be asked.
  ///
  /// [AccountStore.refresh] swallows its failures on purpose — it runs in the
  /// background and an error banner nobody asked for is noise — which means a
  /// plan that could not be *read* is indistinguishable from no plan at all.
  /// It stops being indistinguishable here: unknown never claims the user has
  /// no plan, because telling somebody who is paying that they are not is the
  /// worse of the two errors.
  final bool known;

  const Entitlement({
    this.canSpendManaged = false,
    this.includedProviders = const {},
    this.overCeiling = false,
    this.known = true,
  });

  /// No plan, and that is a fact rather than a failure to ask.
  static const Entitlement none = Entitlement();

  /// The server could not be asked.
  static const Entitlement unknown = Entitlement(known: false);
}

/// Decides which credential a provider call uses. Pure, so the rule can be
/// asserted without a network, a server, or an account.
///
/// **Membership first, the user's own key second.** The user pays monthly, so
/// the plan should be the thing that gets spent. The fallback is what makes
/// reaching the ceiling *degrade* rather than stop: the turn keeps working on
/// their own key instead of failing with a billing message.
///
/// Returns null when neither is available, which is a real state and not an
/// error — the caller turns it into a sentence naming what is missing.
ProviderAccess? resolveAccess(
  String provider, {
  required Entitlement entitlement,
  required String? ownKey,
  required Uri Function(String provider) proxyBase,
  required Map<String, String> Function() sessionHeaders,
}) {
  final covered = entitlement.canSpendManaged &&
      entitlement.includedProviders.contains(provider);

  if (covered) {
    return ManagedAccess(
      base: proxyBase(provider),
      headers: sessionHeaders(),
    );
  }

  if (ownKey != null && ownKey.isNotEmpty) return DirectKey(ownKey);

  return null;
}
