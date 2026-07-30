import 'anthropic_api_config.dart';
import 'anthropic_client.dart';
import 'flux_api_config.dart';
import 'flux_client.dart';
import 'gemini_api_config.dart';
import 'gemini_client.dart';
import 'heygen_api_config.dart';
import 'heygen_client.dart';
import 'openai_compatible_client.dart';
import 'openai_image_client.dart';
import 'elevenlabs_client.dart';
import 'fal_client.dart';
import 'replicate_client.dart';
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
    ProviderCapability.code,
    ProviderCapability.image,
    ProviderCapability.search,
  },
  models: const [
    ProviderModel(
      id: GeminiApiConfig.flashModel,
      displayName: 'Gemini 2.5 Flash',
      capabilities: {
        ProviderCapability.chat,
        ProviderCapability.code,
        ProviderCapability.routing,
      },
    ),
    ProviderModel(
      id: GeminiApiConfig.proModel,
      displayName: 'Gemini 2.5 Pro',
      capabilities: {ProviderCapability.chat, ProviderCapability.code},
    ),
    ProviderModel(
      id: GeminiApiConfig.imageModel,
      displayName: 'Gemini 2.5 Flash Image',
      capabilities: {ProviderCapability.image},
    ),
  ],
  // Gemini leads on image; it is a fallback for text and search behind Claude.
  // Code sits at the same rank as chat: without it, a Gemini-only user asking
  // for a page matched no code-capable provider at all and silently got the
  // simulated demo page instead of their own key's answer.
  preferenceRanks: const {
    ProviderCapability.image: 0,
    ProviderCapability.search: 1,
    ProviderCapability.chat: 2,
    ProviderCapability.code: 2,
  },
  hintPrefix: 'AIza',
  guidanceText:
      'Powers image generation and is a fallback for chat and grounded '
      'search. Stored only in this browser; calls go direct to Google.',
  consoleUrl: 'aistudio.google.com',
);

/// OpenAI, Groq, OpenRouter and Mistral all speak the OpenAI chat-completions
/// wire shape, so they share one client and differ only by this data.
const _llmCapabilities = {
  ProviderCapability.chat,
  ProviderCapability.code,
  ProviderCapability.writing,
  ProviderCapability.routing,
};

final openaiDescriptor = ProviderDescriptor(
  id: 'openai',
  displayName: 'OpenAI',
  persistenceKeyName: 'shift_ai.openai_key.v1',
  authScheme: AuthScheme.header,
  clientKind: ProviderClientKind.openAiCompatible,
  baseUrl: 'https://api.openai.com/v1',
  // Image is OpenAI's alone among the four OpenAI-compatible providers: they
  // share the chat-completions shape, not the images endpoint. Without it an
  // OpenAI-only user asking for a picture matched no image provider and got
  // the simulated procedural artwork while their key sat unused.
  // Video via Sora. OpenAI is the only provider here that renders a clip from
  // a prompt; Heygen renders a talking head, which is the avatar capability.
  capabilities: const {
    ..._llmCapabilities,
    ProviderCapability.image,
    ProviderCapability.video,
  },
  models: const [
    ProviderModel(id: 'gpt-4o', displayName: 'GPT-4o'),
    ProviderModel(id: 'gpt-4o-mini', displayName: 'GPT-4o mini'),
    ProviderModel(
      id: OpenAiImageClient.defaultModel,
      displayName: 'GPT Image 1',
      capabilities: {ProviderCapability.image},
    ),
  ],
  preferenceRanks: const {
    ProviderCapability.chat: 1,
    ProviderCapability.code: 1,
    ProviderCapability.writing: 1,
    ProviderCapability.routing: 1,
    // Last among the image providers. gpt-image-1 needs a verified
    // organization, which the others do not, so a key that works for chat can
    // still fail here — a poor default when another image key is present.
    ProviderCapability.image: 4,
    ProviderCapability.video: 0,
  },
  hintPrefix: 'sk-',
  guidanceText: 'Chat, code, writing and image generation with GPT models. '
      'Stored only in this browser; calls go direct to OpenAI.',
  consoleUrl: 'platform.openai.com',
);

final groqDescriptor = ProviderDescriptor(
  id: 'groq',
  displayName: 'Groq',
  persistenceKeyName: 'shift_ai.groq_key.v1',
  authScheme: AuthScheme.header,
  clientKind: ProviderClientKind.openAiCompatible,
  baseUrl: 'https://api.groq.com/openai/v1',
  capabilities: _llmCapabilities,
  models: const [
    ProviderModel(
        id: 'llama-3.3-70b-versatile', displayName: 'Llama 3.3 70B'),
    ProviderModel(
        id: 'llama-3.1-8b-instant', displayName: 'Llama 3.1 8B'),
  ],
  preferenceRanks: const {
    ProviderCapability.chat: 3,
    ProviderCapability.code: 3,
    ProviderCapability.writing: 3,
    ProviderCapability.routing: 3,
  },
  hintPrefix: 'gsk_',
  guidanceText: 'Very fast open-model inference (Llama). Stored only in this '
      'browser; calls go direct to Groq.',
  consoleUrl: 'console.groq.com',
);

final mistralDescriptor = ProviderDescriptor(
  id: 'mistral',
  displayName: 'Mistral',
  persistenceKeyName: 'shift_ai.mistral_key.v1',
  authScheme: AuthScheme.header,
  clientKind: ProviderClientKind.openAiCompatible,
  baseUrl: 'https://api.mistral.ai/v1',
  capabilities: _llmCapabilities,
  models: const [
    ProviderModel(id: 'mistral-large-latest', displayName: 'Mistral Large'),
    ProviderModel(id: 'mistral-small-latest', displayName: 'Mistral Small'),
  ],
  preferenceRanks: const {
    ProviderCapability.chat: 4,
    ProviderCapability.code: 4,
    ProviderCapability.writing: 4,
    ProviderCapability.routing: 4,
  },
  hintPrefix: '',
  guidanceText: 'European open-weight models. Stored only in this browser; '
      'calls go direct to Mistral.',
  consoleUrl: 'console.mistral.ai',
);

final openrouterDescriptor = ProviderDescriptor(
  id: 'openrouter',
  displayName: 'OpenRouter',
  persistenceKeyName: 'shift_ai.openrouter_key.v1',
  authScheme: AuthScheme.header,
  clientKind: ProviderClientKind.openAiCompatible,
  baseUrl: 'https://openrouter.ai/api/v1',
  extraHeaders: const {
    'HTTP-Referer': 'https://shiftai.club',
    'X-Title': 'SHIFT AI',
  },
  capabilities: _llmCapabilities,
  models: const [
    ProviderModel(
        id: 'openai/gpt-4o', displayName: 'GPT-4o (OpenRouter)'),
    ProviderModel(
        id: 'anthropic/claude-3.5-sonnet',
        displayName: 'Claude 3.5 Sonnet (OpenRouter)'),
    ProviderModel(
        id: 'meta-llama/llama-3.3-70b-instruct',
        displayName: 'Llama 3.3 70B (OpenRouter)'),
  ],
  preferenceRanks: const {
    ProviderCapability.chat: 5,
    ProviderCapability.code: 5,
    ProviderCapability.writing: 5,
    ProviderCapability.routing: 5,
  },
  hintPrefix: 'sk-or-',
  guidanceText: 'One key, many models routed through OpenRouter. Stored only '
      'in this browser; calls go direct to OpenRouter.',
  consoleUrl: 'openrouter.ai/keys',
);

/// Black Forest Labs (FLUX) — high-quality image generation via an async
/// submit/poll API. Browser-direct calls may be blocked by CORS, hence the
/// caution line.
final fluxDescriptor = ProviderDescriptor(
  id: 'flux',
  displayName: 'Black Forest Labs (FLUX)',
  persistenceKeyName: 'shift_ai.flux_key.v1',
  authScheme: AuthScheme.header,
  clientKind: ProviderClientKind.flux,
  baseUrl: FluxApiConfig.base,
  capabilities: const {ProviderCapability.image},
  models: const [
    ProviderModel(
      id: FluxApiConfig.proModel,
      displayName: 'FLUX 1.1 Pro',
      capabilities: {ProviderCapability.image},
    ),
    ProviderModel(
      id: FluxApiConfig.devModel,
      displayName: 'FLUX.1 dev',
      capabilities: {ProviderCapability.image},
    ),
  ],
  // Gemini leads on image; Flux is the next choice.
  preferenceRanks: const {ProviderCapability.image: 1},
  hintPrefix: '',
  guidanceText:
      'High-quality image generation with FLUX. Stored only in this browser.',
  consoleUrl: 'dashboard.bfl.ai',
  corsBlocked: true,
  browserWarning:
      'FLUX does not allow direct browser calls, so this key only works in '
      'the downloaded app — not the website.',
);

/// Heygen — talking-avatar video generation. The app has no in-app video
/// player, so a finished job is shown in the existing video card with an
/// "Open in Heygen" link. Browser-direct calls are CORS-risky.
final heygenDescriptor = ProviderDescriptor(
  id: 'heygen',
  displayName: 'Heygen (avatars)',
  persistenceKeyName: 'shift_ai.heygen_key.v1',
  authScheme: AuthScheme.header,
  clientKind: ProviderClientKind.heygen,
  baseUrl: HeygenApiConfig.base,
  // Avatar-from-script only — not generic text-to-video, so it does not
  // advertise the plain `video` capability (that route stays on the mock).
  // The talkingAvatar / scriptedVideo composition paths use it directly when a
  // key is present.
  capabilities: const {ProviderCapability.avatar},
  models: const [
    ProviderModel(
      id: HeygenApiConfig.model,
      displayName: 'Heygen Avatar',
      capabilities: {ProviderCapability.avatar},
    ),
  ],
  preferenceRanks: const {ProviderCapability.avatar: 0},
  hintPrefix: '',
  guidanceText: 'Talking-avatar videos from a script. Rendered by Heygen and '
      'opened in a new tab (no in-app player). Stored only in this browser.',
  consoleUrl: 'app.heygen.com',
  corsBlocked: true,
  browserWarning:
      'Heygen does not allow direct browser calls, so this key only works in '
      'the downloaded app — not the website.',
);

/// Replicate — a marketplace of hosted models. Wired for image generation
/// (FLUX Schnell by default), which is what a chat app reaches for most.
final replicateDescriptor = ProviderDescriptor(
  id: 'replicate',
  displayName: 'Replicate',
  persistenceKeyName: 'shift_ai.replicate_key.v1',
  authScheme: AuthScheme.header,
  clientKind: ProviderClientKind.replicate,
  baseUrl: ReplicateClient.base,
  capabilities: const {ProviderCapability.image},
  models: const [
    ProviderModel(
      id: ReplicateClient.defaultModel,
      displayName: 'FLUX Schnell (Replicate)',
      capabilities: {ProviderCapability.image},
    ),
  ],
  // Behind Gemini and Flux's own API, ahead of OpenAI: Replicate runs the same
  // FLUX weights, and unlike gpt-image-1 it needs no organization verification.
  preferenceRanks: const {ProviderCapability.image: 2},
  hintPrefix: 'r8_',
  guidanceText: 'Image generation through Replicate\'s hosted models. Stored '
      'only in this browser; calls go direct to Replicate.',
  consoleUrl: 'replicate.com/account/api-tokens',
  // Replicate sends no CORS headers at all, so a browser cannot call it —
  // confirmed by a user's key test failing with "Failed to execute fetch"
  // before any request was even authorized. It works in the installed app.
  corsBlocked: true,
  browserWarning:
      'Replicate does not allow direct browser calls, so this key only works '
      'in the downloaded app — not the website.',
);

/// fal.ai — fast hosted image models. Synchronous, so a picture is one round
/// trip rather than submit-and-poll.
final falDescriptor = ProviderDescriptor(
  id: 'fal',
  displayName: 'fal.ai',
  persistenceKeyName: 'shift_ai.fal_key.v1',
  authScheme: AuthScheme.header,
  clientKind: ProviderClientKind.fal,
  baseUrl: FalClient.base,
  capabilities: const {ProviderCapability.image},
  models: const [
    ProviderModel(
      id: FalClient.defaultModel,
      displayName: 'FLUX Schnell (fal)',
      capabilities: {ProviderCapability.image},
    ),
  ],
  preferenceRanks: const {ProviderCapability.image: 3},
  hintPrefix: '',
  guidanceText: 'Fast image generation through fal.ai. Stored only in this '
      'browser; calls go direct to fal.',
  consoleUrl: 'fal.ai/dashboard/keys',
  corsBlocked: true,
  browserWarning:
      'fal expects calls through its own proxy rather than straight from a '
      'browser, so this key only works in the downloaded app.',
);

/// ElevenLabs — text to speech. The first provider to advertise
/// [ProviderCapability.voice]: until now every voiceover came from the local
/// synthesizer, which is a tone, not a voice.
final elevenLabsDescriptor = ProviderDescriptor(
  id: 'elevenlabs',
  displayName: 'ElevenLabs',
  persistenceKeyName: 'shift_ai.elevenlabs_key.v1',
  authScheme: AuthScheme.header,
  clientKind: ProviderClientKind.elevenLabs,
  baseUrl: ElevenLabsClient.base,
  capabilities: const {ProviderCapability.voice},
  models: const [
    ProviderModel(
      id: ElevenLabsClient.defaultModel,
      displayName: 'Eleven Multilingual v2',
      capabilities: {ProviderCapability.voice},
    ),
  ],
  preferenceRanks: const {ProviderCapability.voice: 0},
  hintPrefix: 'sk_',
  guidanceText: 'Real spoken voiceovers instead of the built-in synthesizer. '
      'Stored only in this browser; calls go direct to ElevenLabs.',
  consoleUrl: 'elevenlabs.io',
  // ElevenLabs does serve CORS headers, so it is a caution rather than a
  // certainty — some plans and endpoints differ.
  browserWarning:
      'If a key test or a voiceover fails with a network error in the browser, '
      'the same key will work in the downloaded app.',
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
        openaiDescriptor,
        geminiDescriptor,
        groqDescriptor,
        mistralDescriptor,
        openrouterDescriptor,
        fluxDescriptor,
        replicateDescriptor,
        falDescriptor,
        elevenLabsDescriptor,
        heygenDescriptor,
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
/// tests can supply fakes. Only the validation surface is exposed here — the
/// streaming chat clients are held directly by `RealChatService`.
///
/// Fixed-endpoint providers (Anthropic, Gemini, and later Flux/Heygen) expose a
/// simple [KeyValidatable]. OpenAI-compatible providers share one client whose
/// validation needs the descriptor's base URL / model, so they are validated
/// through [_openAi] with descriptor data rather than the per-kind map.
class ClientRegistry {
  final Map<ProviderClientKind, KeyValidatable Function()> _factories;
  final Map<ProviderClientKind, KeyValidatable> _cache = {};
  final OpenAiCompatibleClient Function() _openAiFactory;
  OpenAiCompatibleClient? _openAi;

  ClientRegistry({
    Map<ProviderClientKind, KeyValidatable Function()>? factories,
    OpenAiCompatibleClient Function()? openAiClient,
  })  : _factories = {
          ProviderClientKind.anthropic: () => AnthropicClient(),
          ProviderClientKind.gemini: () => GeminiClient(),
          ProviderClientKind.flux: () => FluxClient(),
          ProviderClientKind.heygen: () => HeygenClient(),
          ProviderClientKind.elevenLabs: () => ElevenLabsClient(),
          ProviderClientKind.replicate: () => ReplicateClient(),
          ProviderClientKind.fal: () => FalClient(),
          ...?factories,
        },
        _openAiFactory = openAiClient ?? (() => OpenAiCompatibleClient());

  /// The shared OpenAI-compatible client, built once.
  OpenAiCompatibleClient get openAi => _openAi ??= _openAiFactory();

  /// The validator for [kind], or null if no client is registered for it yet
  /// (e.g. a descriptor whose client ships in a later phase). Note the
  /// OpenAI-compatible kind is handled by [validateKey] directly, not here.
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
    if (descriptor.clientKind == ProviderClientKind.openAiCompatible) {
      final model = descriptor.defaultModelId;
      if (descriptor.baseUrl == null || model == null) {
        return 'Key validation for ${descriptor.displayName} is not available '
            'yet.';
      }
      return openAi.validateKey(
        apiKey: apiKey,
        baseUrl: descriptor.baseUrl!,
        model: model,
        providerName: descriptor.displayName,
        consoleUrl: descriptor.consoleUrl,
        extraHeaders: descriptor.extraHeaders,
      );
    }
    final validator = validatorFor(descriptor.clientKind);
    if (validator == null) {
      return 'Key validation for ${descriptor.displayName} is not available '
          'yet.';
    }
    return validator.validateKey(apiKey);
  }
}
