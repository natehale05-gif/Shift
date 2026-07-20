import 'dart:convert';

import '../../models/studio_type.dart';
import '../providers/anthropic_api_config.dart';
import '../providers/anthropic_client.dart';
import '../providers/gemini_client.dart';
import '../studio_response_bank.dart';

/// What kind of executor a prompt needs — the middleware AI's routing
/// decision, independent of which provider ends up serving it.
enum ChatRoute { chat, code, writing, imageGen, webSearch, deepResearch, video, audio }

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
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

/// Maps the existing keyword tables onto routes — the no-key (and
/// LLM-parse-failure) fallback, so routing never breaks.
ChatRoute keywordRoute(String input) {
  return switch (StudioResponseBank.detectStudio(input)) {
    StudioType.imageStudio => ChatRoute.imageGen,
    StudioType.videoStudio => ChatRoute.video,
    StudioType.voiceAvatarStudio => ChatRoute.audio,
    StudioType.musicStudio => ChatRoute.audio,
    StudioType.copyScriptsStudio => ChatRoute.writing,
    StudioType.codeStudio => ChatRoute.code,
    StudioType.middleware => StudioResponseBank.wantsWebSearch(input)
        ? ChatRoute.webSearch
        : ChatRoute.chat,
  };
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

  ModelRouter({AnthropicClient? client, GeminiClient? geminiClient})
      : _client = client ?? AnthropicClient(),
        _gemini = geminiClient ?? GeminiClient();

  Future<ChatRoute> route({
    required String input,
    String? anthropicKey,
    String? geminiKey,
  }) async {
    final hasAnthropic = anthropicKey != null && anthropicKey.isNotEmpty;
    final hasGemini = geminiKey != null && geminiKey.isNotEmpty;
    if (!hasAnthropic && !hasGemini) {
      return keywordRoute(input);
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
}
