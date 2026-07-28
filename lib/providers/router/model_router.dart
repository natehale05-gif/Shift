import '../../turn/studio_detection.dart';
import 'dart:convert';

import '../../data/models/studio_type.dart';
import '../../data/stores/api_keys_store.dart';
import '../clients/anthropic_api_config.dart';
import '../clients/anthropic_client.dart';
import '../clients/gemini_client.dart';
import '../clients/openai_compatible_client.dart';
import '../clients/provider_capability.dart';
import '../clients/provider_registry.dart';
import '../../features/studios/studio_response_bank.dart';

/// What kind of executor a prompt needs — the middleware AI's routing
/// decision, independent of which provider ends up serving it.
enum ChatRoute {
  chat,
  code,
  writing,
  imageGen,
  webSearch,
  deepResearch,
  video,
  audio,
  voice,
  avatar,
  translate,
  deck,
  shortReels,
  brandPack,
}

extension ChatRouteStudio on ChatRoute {
  /// The studio identity shown on the routing chip.
  StudioType get studioType => switch (this) {
        ChatRoute.chat => StudioType.middleware,
        ChatRoute.code => StudioType.codeStudio,
        ChatRoute.writing => StudioType.copyScriptsStudio,
        ChatRoute.imageGen => StudioType.imageStudio,
        ChatRoute.webSearch => StudioType.middleware,
        ChatRoute.deepResearch => StudioType.middleware,
        ChatRoute.video => StudioType.videoStudio,
        ChatRoute.audio => StudioType.musicStudio,
        ChatRoute.voice => StudioType.voiceStudio,
        ChatRoute.avatar => StudioType.avatarStudio,
        ChatRoute.translate => StudioType.translateStudio,
        ChatRoute.deck => StudioType.deckStudio,
        ChatRoute.shortReels => StudioType.shortReelsStudio,
        ChatRoute.brandPack => StudioType.brandPackStudio,
      };
}

/// Parses the router model's strict-JSON reply, e.g.
/// `{"route":"code"}`. Returns null if it isn't valid.
ChatRoute? parseRouteJson(String text) {
  try {
    // Models occasionally wrap JSON in a code fence despite instructions.
    final cleaned = text
        .replaceAll(RegExp(r'^```(json)?', multiLine: true), '')
        .replaceAll('```', '')
        .trim();
    final decoded = jsonDecode(cleaned) as Map<String, dynamic>;
    return switch (decoded['route'] as String?) {
      'chat' => ChatRoute.chat,
      'code' => ChatRoute.code,
      'writing' => ChatRoute.writing,
      'image_gen' => ChatRoute.imageGen,
      'web_search' => ChatRoute.webSearch,
      'deep_research' => ChatRoute.deepResearch,
      'video' => ChatRoute.video,
      'audio' => ChatRoute.audio,
      'voice' => ChatRoute.voice,
      'avatar' => ChatRoute.avatar,
      'translate' => ChatRoute.translate,
      'deck' => ChatRoute.deck,
      'short_reels' => ChatRoute.shortReels,
      'brand_pack' => ChatRoute.brandPack,
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

/// The route that continues a given studio's request — used both by the
/// keyword fallback below and to keep a reply to our own clarifying
/// question ("navy blue") on the same studio rather than reclassifying it.
ChatRoute routeForStudio(StudioType studio) => switch (studio) {
      StudioType.imageStudio => ChatRoute.imageGen,
      StudioType.videoStudio => ChatRoute.video,
      StudioType.voiceAvatarStudio => ChatRoute.audio,
      StudioType.musicStudio => ChatRoute.audio,
      StudioType.copyScriptsStudio => ChatRoute.writing,
      StudioType.codeStudio => ChatRoute.code,
      StudioType.middleware => ChatRoute.chat,
      StudioType.voiceStudio => ChatRoute.voice,
      StudioType.avatarStudio => ChatRoute.avatar,
      StudioType.translateStudio => ChatRoute.translate,
      StudioType.deckStudio => ChatRoute.deck,
      StudioType.shortReelsStudio => ChatRoute.shortReels,
      StudioType.brandPackStudio => ChatRoute.brandPack,
    };

/// Maps the existing keyword tables onto routes — the no-key (and
/// LLM-parse-failure) fallback, so routing never breaks.
ChatRoute keywordRoute(String input) {
  final studio = StudioDetection.detectStudio(input);
  if (studio == StudioType.middleware) {
    return StudioDetection.wantsWebSearch(input)
        ? ChatRoute.webSearch
        : ChatRoute.chat;
  }
  return routeForStudio(studio);
}

const _routerSystemPrompt =
    'You are a routing classifier. Read the user\'s message and respond '
    'with ONLY minified JSON of the form '
    '{"route":"chat|code|writing|image_gen|web_search|deep_research|video|audio"} '
    '— no prose, no code fences. '
    'code = programming/build-a-page requests; writing = marketing copy, '
    'scripts, captions; image_gen = wants a picture generated; web_search = '
    'needs fresh information from the web; deep_research = asks for '
    'in-depth multi-source research; video/audio = wants those media '
    'generated; chat = everything else.';

/// The middleware routing brain: a small fast LLM classification (Haiku
/// when an Anthropic key exists, Gemini Flash when only a Google key does)
/// with one retry, always falling back to the keyword tables.
class ModelRouter {
  final AnthropicClient _client;
  final GeminiClient _gemini;
  final OpenAiCompatibleClient _openAi;
  final ProviderRegistry _registry;

  /// Optional key store. When neither an Anthropic nor a Gemini key is present,
  /// the router uses this (plus the registry) to classify with an
  /// OpenAI-compatible provider the user does have a key for, instead of
  /// dropping straight to the keyword tables. Injected via the constructor so
  /// the frozen [route] signature stays intact.
  final ApiKeysStore? _keys;

  ModelRouter({
    AnthropicClient? client,
    GeminiClient? geminiClient,
    OpenAiCompatibleClient? openAiClient,
    ProviderRegistry? registry,
    ApiKeysStore? keys,
  })  : _client = client ?? AnthropicClient(),
        _gemini = geminiClient ?? GeminiClient(),
        _openAi = openAiClient ?? OpenAiCompatibleClient(),
        _registry = registry ?? ProviderRegistry.defaults(),
        _keys = keys;

  Future<ChatRoute> route({
    required String input,
    String? anthropicKey,
    String? geminiKey,
  }) async {
    final hasAnthropic = anthropicKey != null && anthropicKey.isNotEmpty;
    final hasGemini = geminiKey != null && geminiKey.isNotEmpty;
    if (!hasAnthropic && !hasGemini) {
      // Step 3: an OpenAI-compatible key can still classify; else keywords.
      return (await _routeViaOpenAi(input)) ?? keywordRoute(input);
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final reply = hasAnthropic
            ? await _client.complete(
                apiKey: anthropicKey,
                model: AnthropicApiConfig.haikuModel,
                systemPrompt: _routerSystemPrompt,
                prompt: input,
                maxTokens: 60,
              )
            : await _gemini.complete(
                apiKey: geminiKey!,
                systemPrompt: _routerSystemPrompt,
                prompt: input,
              );
        final route = parseRouteJson(reply);
        if (route != null) return route;
      } catch (_) {
        break; // network/API problem: no point retrying the same failure
      }
    }
    return keywordRoute(input);
  }

  /// Classifies with the best routing-capable OpenAI-compatible provider the
  /// user has a key for. Returns null when none is available or the call fails,
  /// so the caller falls back to the keyword tables.
  Future<ChatRoute?> _routeViaOpenAi(String input) async {
    final keys = _keys;
    if (keys == null) return null;
    for (final descriptor
        in _registry.providersFor(ProviderCapability.routing)) {
      if (descriptor.clientKind != ProviderClientKind.openAiCompatible) continue;
      if (!keys.hasKey(descriptor.id)) continue;
      final model = descriptor.modelForCapability(ProviderCapability.routing)?.id ??
          descriptor.defaultModelId;
      if (model == null || descriptor.baseUrl == null) return null;
      try {
        final reply = await _openAi.complete(
          apiKey: keys.keyFor(descriptor.id),
          baseUrl: descriptor.baseUrl!,
          model: model,
          systemPrompt: _routerSystemPrompt,
          prompt: input,
          maxTokens: 60,
          extraHeaders: descriptor.extraHeaders,
        );
        return parseRouteJson(reply);
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
