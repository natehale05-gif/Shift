import '../providers/access.dart';
import '../providers/failure_text.dart';
import 'account_store.dart';
import 'api_keys_store.dart';

/// Where a turn's credential comes from: the plan first, the device second.
///
/// **One implementation, because three was the bug.** Chat, Notes and Code each
/// built their own `usable`/`access` pair, and all three asked only
/// [ApiKeysStore]. So a member with SHIFT's keys on the server and none on
/// their device was told *"No provider is set up"* — the vault, the plan and
/// the metered proxy were never consulted, and the membership bought nothing.
/// The rule having one home is what stops that recurring per surface.
///
/// The split between the two methods is not stylistic. [usable] answers
/// *before* any request, because routing has to choose a provider first; it is
/// therefore synchronous and reads only cached facts. [access] runs once a
/// provider is chosen and may go to the network, because a proxy call carries a
/// session token with a short life that is fetched per call rather than held.
class ProviderAccessSource {
  /// Keys on this device. Null in a build or a test with no key store.
  final ApiKeysStore? keys;

  /// The account, for what the plan covers. Null when the app has no server
  /// behind it — in which case this degrades to exactly the old behaviour.
  final AccountStore? account;

  const ProviderAccessSource({this.keys, this.account});

  /// Nothing but the device's keys — the shape every surface had before the
  /// membership could pay for anything. Kept as a named constructor so a test
  /// can say which of the two worlds it is in.
  const ProviderAccessSource.deviceOnly(ApiKeysStore? keys)
      : this(keys: keys);

  /// What the plan can pay for right now, as far as this device knows.
  Entitlement get entitlement => account?.entitlement ?? Entitlement.none;

  /// Whether a call to [providerId] can be paid for at all.
  ///
  /// **The plan counts here, and its absence is the whole defect this fixes.**
  /// Routing runs before any credential is resolved, so a provider missing from
  /// this answer is never chosen and the turn fails claiming nothing is set up
  /// — which is what a paying member saw.
  bool usable(String providerId) =>
      (account?.spendableProviders.contains(providerId) ?? false) ||
      (keys?.has(providerId) ?? false);

  /// The credential for a call to [providerId], or null when there is none.
  ///
  /// Membership first, the user's own key second — see [resolveAccess], which
  /// owns that rule. The proxy target is fetched before the decision because it
  /// needs a fresh token; when the account cannot supply one the decision still
  /// runs and falls through to the device's key, so a server that is down
  /// degrades to BYOK instead of stopping the turn.
  Future<ProviderAccess?> access(String providerId) async {
    final managed = await account?.managedProviderCall(providerId);

    return resolveAccess(
      providerId,
      // Downgraded when the proxy could not be reached: claiming the plan
      // covers a call we have no way to make would produce a request with no
      // credential, and a 401 that reads as a bad key.
      entitlement: managed == null ? _withoutManaged : entitlement,
      ownKey: keys?.get(providerId),
      proxyBase: (_) => managed!.base,
      sessionHeaders: () => managed!.headers,
    );
  }

  /// Why nothing can run a step producing [what].
  ///
  /// Passed to the executors so the card names the actual state instead of the
  /// one sentence that used to cover five of them.
  String explain(String what) => sentenceForNoProvider(
        what,
        entitlement: entitlement,
        signedIn: account?.isSignedIn ?? false,
      );

  /// [entitlement] with spending switched off, keeping [Entitlement.known] so
  /// the sentence for a plan that exists but could not be spent stays right.
  Entitlement get _withoutManaged => Entitlement(
        includedProviders: entitlement.includedProviders,
        overCeiling: entitlement.overCeiling,
        known: entitlement.known,
      );
}
