import 'anthropic_api_config.dart';
import 'anthropic_client.dart';
import 'gemini_api_config.dart';
import 'gemini_client.dart';
import 'provider_capability.dart';
import 'provider_descriptor.dart';

/// Anything that can cheaply check one of its keys. Returns null when the key
/// works, else a human-readable problem string. Every provider client
/// implements this; the store and Settings validate keys through it without
/// knowing the concrete client type.
abstract interface class KeyValidatable {
  Future<String?> validateKey(String apiKey);
}

/// The Anthropic (Claude) provider, expressed as data. References the existing
/// [AnthropicApiConfig] constants so there is exactly one source of truth for
/// endpoints and model ids.
final anthropicDescriptor = ProviderDescriptor(
  id: 'anthropic',
  displayName: 'Anthropic (Claude)',
  persistenceKeyName: 'shift_ai.anthropic_key.v1',
  authScheme: AuthScheme.header,
  clientKind: ProviderClientKind.anthropic,
  capabilities: const {
    ProviderCapability.chat,
    ProviderCapability.code,
    ProviderCapability.writing,
    ProviderCapability.routing,
    ProviderCapability.search,
  },
  models: const [
    ProviderModel(
      id: AnthropicApiConfig.defaultModel,
      displayName: 'Claude Opus 4.8',
      capabilities: {
        ProviderCapability.chat,
        ProviderCapability.code,
        ProviderCapability.writing,
      },
    ),
    ProviderModel(
      id: AnthropicApiConfig.sonnetModel,
      displayName: 'Claude Sonnet 5',
      capabilities: {
        ProviderCapability.chat,
        ProviderCapability.code,
        ProviderCapability.writing,
      },
    ),
    ProviderModel(
      id: AnthropicApiConfig.haikuModel,
      displayName: 'Claude Haiku 4.5',
      capabilities: {ProviderCapability.routing},
    ),
  ],
  // Claude is the preferred text/code/writing/routing/search provider.
  preferenceRanks: const {
    ProviderCapability.chat: 0,
    ProviderCapability.code: 0,
    ProviderCapability.writing: 0,
    ProviderCapability.routing: 0,
    ProviderCapability.search: 0,
  },
  hintPrefix: 'sk-ant-',
  guidanceText:
      'Powers chat, code, writing, routing and grounded web search. '
      'Stored only in this browser; calls go direct to Anthropic.',
  consoleUrl: 'console.anthropic.com',
);

/// The Google Gemini provider. Deliberately does **not** advertise
/// [ProviderCapability.voice] — voice output stays on the local synth/mock so
/// the audio-routing degradation matrix is unaffected.
final geminiDescriptor = ProviderDescriptor(
  id: 'gemini',
  displayName: 'Google Gemini',
  persistenceKeyName: 'shift_ai.gemini_key.v1',
  authScheme: AuthScheme.queryParam,
  clientKind: ProviderClientKind.gemini,
  capabilities: const {
    ProviderCapability.chat,
    ProviderCapability.image,
    ProviderCapability.search,
  },
  models: const [
    ProviderModel(
      id: GeminiApiConfig.flashModel,
      displayName: 'Gemini 2.5 Flash',
      capabilities: {ProviderCapability.chat, ProviderCapability.routing},
    ),
    ProviderModel(
      id: GeminiApiConfig.proModel,
      displayName: 'Gemini 2.5 Pro',
      capabilities: {ProviderCapability.chat},
    ),
    ProviderModel(
      id: GeminiApiConfig.imageModel,
      displayName: 'Gemini 2.5 Flash Image',
      capabilities: {ProviderCapability.image},
    ),
  ],
  // Gemini leads on image; it is a fallback for text and search behind Claude.
  preferenceRanks: const {
    ProviderCapability.image: 0,
    ProviderCapability.search: 1,
    ProviderCapability.chat: 2,
  },
  hintPrefix: 'AIza',
  guidanceText:
      'Powers image generation and is a fallback for chat and grounded '
      'search. Stored only in this browser; calls go direct to Google.',
  consoleUrl: 'aistudio.google.com',
);

/// The set of providers the app knows about, plus lookups over them. Pure
/// data — no network, no state — so it is trivially unit-testable and safe to
/// construct anywhere.
class ProviderRegistry {
  final List<ProviderDescriptor> all;

  const ProviderRegistry(this.all);

  /// The built-in providers. Adding a "top model or company" is, in most
  /// cases, one more descriptor in this list.
  factory ProviderRegistry.defaults() => ProviderRegistry([
        anthropicDescriptor,
        geminiDescriptor,
      ]);

  ProviderDescriptor? byId(String id) {
    for (final d in all) {
      if (d.id == id) return d;
    }
    return null;
  }

  /// The provider that owns [modelId] (model ids are globally unique), or null.
  ProviderDescriptor? providerForModel(String modelId) {
    for (final d in all) {
      for (final m in d.models) {
        if (m.id == modelId) return d;
      }
    }
    return null;
  }

  /// The [ProviderModel] for [modelId] across all providers, or null.
  ProviderModel? modelById(String modelId) {
    for (final d in all) {
      for (final m in d.models) {
        if (m.id == modelId) return m;
      }
    }
    return null;
  }

  /// Human label for a model id — the model's own display name, else the id.
  String displayNameForModel(String modelId) =>
      modelById(modelId)?.displayName ?? modelId;

  /// Providers that serve [capability], most-preferred first. This ordering is
  /// the "Auto" decision: the router picks the first one the user has a key
  /// for.
  List<ProviderDescriptor> providersFor(ProviderCapability capability) {
    final matches = [
      for (final d in all)
        if (d.supports(capability)) d,
    ];
    matches.sort((a, b) =>
        a.preferenceRank(capability).compareTo(b.preferenceRank(capability)));
    return matches;
  }
}

/// Lazily builds and caches one client per [ProviderClientKind]. Injectable so
/// tests can supply fakes. Only the [KeyValidatable] surface is exposed here —
/// the streaming chat clients are held directly by `RealChatService`.
class ClientRegistry {
  final Map<ProviderClientKind, KeyValidatable Function()> _factories;
  final Map<ProviderClientKind, KeyValidatable> _cache = {};

  ClientRegistry({Map<ProviderClientKind, KeyValidatable Function()>? factories})
      : _factories = {
          ProviderClientKind.anthropic: () => AnthropicClient(),
          ProviderClientKind.gemini: () => GeminiClient(),
          ...?factories,
        };

  /// The validator for [kind], or null if no client is registered for it yet
  /// (e.g. a descriptor whose client ships in a later phase).
  KeyValidatable? validatorFor(ProviderClientKind kind) {
    final factory = _factories[kind];
    if (factory == null) return null;
    return _cache.putIfAbsent(kind, factory);
  }

  /// Validates [apiKey] against [descriptor]'s client. Returns a problem string
  /// when there is no client wired for the kind, so the caller never silently
  /// reports success for an unvalidatable provider.
  Future<String?> validateKey(
      ProviderDescriptor descriptor, String apiKey) async {
    final validator = validatorFor(descriptor.clientKind);
    if (validator == null) {
      return 'Key validation for ${descriptor.displayName} is not available '
          'yet.';
    }
    return validator.validateKey(apiKey);
  }
}
