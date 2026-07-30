import 'provider_capability.dart';

/// One selectable model within a provider. [id] is **globally unique** across
/// all providers (`claude-*`, `gpt-*`, `gemini-*`, `flux-*`) so a pinned model
/// id resolves back to exactly one provider via the registry.
class ProviderModel {
  final String id;
  final String displayName;

  /// The subset of the provider's capabilities this specific model serves.
  /// Defaults to empty, meaning "inherits the provider's capabilities" — most
  /// chat models do, so callers should treat empty as "same as the provider".
  final Set<ProviderCapability> capabilities;

  const ProviderModel({
    required this.id,
    required this.displayName,
    this.capabilities = const {},
  });
}

/// A provider expressed as data rather than code. Adding a new "top model or
/// company" is, in most cases, just another `ProviderDescriptor` in the
/// registry — the key store, Settings UI, and routing are all driven off this
/// structure. A genuinely new API shape additionally needs a client behind a
/// new [ProviderClientKind].
class ProviderDescriptor {
  /// Stable machine id (`anthropic`, `gemini`, `openai`, `groq`, ...). Used as
  /// the key in the map-backed `ApiKeysStore` and for client dispatch.
  final String id;

  /// Human label shown in Settings and the model picker.
  final String displayName;

  /// The persistence key name under which this provider's API key is stored
  /// (via `PersistenceService.loadApiKey/saveApiKey`). Kept identical to the
  /// historical constants for Anthropic/Gemini so existing saved keys load.
  final String persistenceKeyName;

  final AuthScheme authScheme;
  final ProviderClientKind clientKind;

  /// Base URL for HTTP clients that need one (OpenAI-compatible, Flux, Heygen).
  /// Null for clients that hardcode their endpoints (Anthropic, Gemini).
  final String? baseUrl;

  /// Static headers merged into every request (e.g. OpenRouter's `HTTP-Referer`
  /// / `X-Title`). The auth header is added by the client, not here.
  final Map<String, String> extraHeaders;

  /// Everything this provider can do, in principle.
  final Set<ProviderCapability> capabilities;

  /// The models a user can pin for this provider.
  final List<ProviderModel> models;

  /// Lower is more preferred. Consulted by `providersFor(capability)` to build
  /// the Auto order. A capability absent from the map falls back to
  /// [defaultRank].
  final Map<ProviderCapability, int> preferenceRanks;
  final int defaultRank;

  // ---- Settings copy ----
  /// Short prefix a valid key usually starts with (e.g. `sk-`, `AIza`), shown
  /// as a hint. Empty when there is no stable prefix.
  final String hintPrefix;

  /// One-line guidance under the field.
  final String guidanceText;

  /// Where to create a key.
  final String consoleUrl;

  /// Set for providers whose endpoint may reject browser-direct calls (CORS).
  /// Rendered as a caution line in Settings; null when browser calls are fine.
  final String? browserWarning;

  /// Set when the provider sends no CORS headers, so browser-direct calls
  /// cannot work. See [browserBlocked].
  final bool corsBlocked;

  const ProviderDescriptor({
    required this.id,
    required this.displayName,
    required this.persistenceKeyName,
    required this.authScheme,
    required this.clientKind,
    required this.capabilities,
    required this.models,
    this.baseUrl,
    this.extraHeaders = const {},
    this.preferenceRanks = const {},
    this.defaultRank = 100,
    this.hintPrefix = '',
    this.guidanceText = '',
    this.consoleUrl = '',
    this.browserWarning,
    this.corsBlocked = false,
  });

  bool get isBrowserRisky => browserWarning != null;

  /// Whether this provider's API refuses browser-direct calls outright.
  ///
  /// Distinct from [isBrowserRisky], which is a caution. This is a fact about
  /// the provider: no CORS headers means a browser cannot call it at all, no
  /// matter how good the key is. Auto skips these on web instead of routing a
  /// turn into a wall — a user with an OpenAI key *and* a Replicate key should
  /// get their picture from OpenAI, not a fetch error from Replicate.
  bool get browserBlocked => corsBlocked;

  bool supports(ProviderCapability capability) =>
      capabilities.contains(capability);

  int preferenceRank(ProviderCapability capability) =>
      preferenceRanks[capability] ?? defaultRank;

  /// The models that serve [capability] — a model with an explicit capability
  /// set is filtered on it; a model with an empty set inherits the provider's
  /// capabilities (so it counts if the provider itself supports it).
  List<ProviderModel> modelsFor(ProviderCapability capability) => [
        for (final m in models)
          if (m.capabilities.isEmpty
              ? supports(capability)
              : m.capabilities.contains(capability))
            m,
      ];

  /// The first model serving [capability], or null.
  ProviderModel? modelForCapability(ProviderCapability capability) {
    final matches = modelsFor(capability);
    return matches.isEmpty ? null : matches.first;
  }

  /// The provider's default chat model id, or the first model's id, or null.
  String? get defaultModelId =>
      modelForCapability(ProviderCapability.chat)?.id ??
      (models.isEmpty ? null : models.first.id);
}
