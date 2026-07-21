import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/artifact.dart';
import '../models/attachment.dart';
import '../models/citation.dart';
import '../models/conversation.dart';
import '../models/studio_request.dart';
import '../models/studio_result.dart';
import '../models/studio_type.dart';
import '../state/api_keys_store.dart';
import 'artifact_composition.dart';
import 'audio_synth_service.dart';
import 'chat_service.dart';
import 'deep_research_engine.dart';
import 'mock_chat_service.dart';
import 'procedural_art.dart';
import 'studio_composition.dart';
import 'translate_service.dart';
import 'providers/anthropic_api_config.dart';
import 'providers/anthropic_client.dart';
import 'providers/anthropic_tools.dart';
import 'providers/flux_client.dart';
import 'providers/gemini_api_config.dart';
import 'providers/gemini_client.dart';
import 'providers/heygen_client.dart';
import 'providers/openai_compatible_client.dart';
import 'providers/provider_capability.dart';
import 'providers/provider_descriptor.dart';
import 'providers/provider_registry.dart';
import 'router/model_router.dart';
import 'router/provider_selection.dart';
import 'studio_clarification.dart';
import 'studio_response_bank.dart';

const _uuid = Uuid();

/// Which backend serves a routed request.
enum Executor { anthropic, gemini, mock }

/// The Anthropic/Gemini degradation matrix, preserved as a thin wrapper over
/// the capability-based [chooseProvider] so there is one source of truth for
/// the Auto decision. Given only the two legacy flags, [chooseProvider] can
/// only ever pick Anthropic, Gemini, or nothing (→ mock), reproducing the
/// original nine-combo matrix exactly. Pure — unit-tested.
Executor chooseExecutor(
  ChatRoute route, {
  required bool hasAnthropic,
  required bool hasGemini,
}) {
  final id = chooseProvider(
    route,
    registry: ProviderRegistry.defaults(),
    hasKey: (providerId) =>
        (providerId == 'anthropic' && hasAnthropic) ||
        (providerId == 'gemini' && hasGemini),
  );
  return switch (id) {
    'anthropic' => Executor.anthropic,
    'gemini' => Executor.gemini,
    _ => Executor.mock,
  };
}

/// Live-mode middleware: routes each message (LLM classifier with keyword
/// fallback), then executes on the best available provider. Routes no live
/// provider can serve yet (image/video/audio before a Gemini key exists)
/// fall back to the mock so the request still produces a useful, clearly
/// simulated result.
class RealChatService implements ChatService {
  final ApiKeysStore keys;
  final AnthropicClient _anthropic;
  final GeminiClient _gemini;
  final OpenAiCompatibleClient _openAi;
  final FluxClient _flux;
  final HeygenClient _heygen;
  final ProviderRegistry _registry;
  final ModelRouter _router;
  final MockChatService _mockFallback;

  RealChatService({
    required this.keys,
    AnthropicClient? anthropicClient,
    GeminiClient? geminiClient,
    OpenAiCompatibleClient? openAiClient,
    FluxClient? fluxClient,
    HeygenClient? heygenClient,
    ProviderRegistry? registry,
    ModelRouter? router,
    MockChatService? mockFallback,
  })  : _anthropic = anthropicClient ?? AnthropicClient(),
        _gemini = geminiClient ?? GeminiClient(),
        _openAi = openAiClient ?? OpenAiCompatibleClient(),
        _flux = fluxClient ?? FluxClient(),
        _heygen = heygenClient ?? HeygenClient(),
        _registry = registry ?? ProviderRegistry.defaults(),
        _router = router ??
            ModelRouter(
              client: anthropicClient,
              geminiClient: geminiClient,
              openAiClient: openAiClient,
              registry: registry,
              keys: keys,
            ),
        _mockFallback = mockFallback ?? MockChatService();

  @override
  Stream<ChatEvent> sendMessage({
    required Conversation conversation,
    required String userInput,
    StudioRequest? structuredRequest,
    List<Attachment> attachments = const [],
    ChatOptions options = ChatOptions.none,
  }) {
    final controller = StreamController<ChatEvent>();
    _run(controller, conversation, userInput, structuredRequest, attachments,
        options);
    return controller.stream;
  }

  Future<void> _run(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    StudioRequest? structuredRequest,
    List<Attachment> attachments,
    ChatOptions options,
  ) async {
    try {
      // A structured Image Studio form runs real generation when a Google
      // key exists; other structured forms and deep research keep their
      // simulated flows until their live executors ship.
      if (structuredRequest != null) {
        if (structuredRequest is ImageRequest) {
          final imageId = chooseProvider(ChatRoute.imageGen,
              registry: _registry, hasKey: keys.hasKey);
          if (imageId != null) {
            await _runImage(controller, imageId, structuredRequest.prompt);
            return;
          }
        }
        await _delegateToMock(controller, conversation, userInput,
            structuredRequest, attachments, options);
        return;
      }
      if (options.deepResearch) {
        if (keys.isLive) {
          await _runDeepResearch(controller, conversation, userInput);
        } else {
          await _delegateToMock(controller, conversation, userInput, null,
              attachments, options);
        }
        return;
      }

      // A terse follow-up to our own clarifying question ("navy blue")
      // continues the same studio request rather than being reclassified
      // from scratch — regardless of whether the question was asked by the
      // mock or a live provider (both end their questions with '?').
      final pending = findPendingClarification(conversation);

      // One composition decision for the turn (see studio_composition).
      // pageAssembly ("build a website with photos") forces Code Studio
      // directly rather than trusting the classifier to prefer it over the
      // image keywords in the same prompt — _runAnthropicChat below embeds
      // the photos once the page exists.
      final plan = pending == null
          ? planComposition(conversation, userInput)
          : CompositionPlan.none;
      final wantsBoth = plan.kind == CompositionKind.pageAssembly;

      // Copy & Scripts writes a script, then a media studio produces from it.
      // The write step is real (Claude/Gemini); the voice/video/music is
      // synthesized, since no live provider generates those.
      if (isCopyFed(plan.kind)) {
        await _runCopyFedMedia(controller, plan.kind, userInput);
        await controller.close();
        return;
      }

      // Media pairs: a talking avatar (portrait + voice) or scored narration
      // (voice over a music bed). The portrait is real (Gemini) when a Google
      // key exists; the voiceover script is real (Claude/Gemini); the audio
      // itself is synthesized.
      if (isMediaPair(plan.kind)) {
        await _runMediaPair(controller, plan.kind, userInput);
        await controller.close();
        return;
      }

      // "Add background music / a video to the website": audio and video are
      // always synthesized (no live provider), so the mock performs the embed
      // into the existing artifact. Image edits keep the live image path
      // below (Gemini/Flux, or the mock when no image key exists).
      if (plan.kind == CompositionKind.editArtifact &&
          plan.editKind != ArtifactMediaKind.image) {
        await _delegateToMock(
            controller, conversation, userInput, null, attachments, options);
        return;
      }

      // An explicit model pin bypasses routing entirely and dispatches to the
      // pinned model's provider (as long as the user has that key). Claude
      // pins fall through to the existing Anthropic path below, which already
      // reads options.modelPin.
      final pin = options.modelPin;
      if (pin != null) {
        final provider = _registry.providerForModel(pin);
        if (provider != null && keys.hasKey(provider.id)) {
          if (provider.clientKind == ProviderClientKind.openAiCompatible) {
            await _runOpenAiChat(controller, conversation, userInput,
                attachments, options, provider,
                model: pin);
            await controller.close();
            return;
          }
          if (provider.id == 'gemini') {
            await _runGeminiChat(controller, conversation, userInput,
                attachments, options, ChatRoute.chat, model: pin);
            await controller.close();
            return;
          }
        }
      }

      final route = pin != null
          ? ChatRoute.chat // an explicit model pin bypasses routing
          : pending != null
              ? routeForStudio(pending.$1)
              : wantsBoth
                  ? ChatRoute.code
                  : await _router.route(
                      input: userInput,
                      anthropicKey: keys.anthropicKey,
                      geminiKey: keys.geminiKey,
                    );

      // Translate is a real deliverable: the best text provider does the
      // translation, returned as a downloadable TranslateResult.
      if (route == ChatRoute.translate) {
        await _runTranslate(controller, userInput);
        await controller.close();
        return;
      }

      // Auto: pick the best available provider for the route's capability.
      final providerId =
          chooseProvider(route, registry: _registry, hasKey: keys.hasKey);
      final provider = providerId == null ? null : _registry.byId(providerId);

      final pageContributors = plan.kind == CompositionKind.pageAssembly
          ? plan.contributors
          : const <StudioType>{};

      switch (provider?.clientKind) {
        case ProviderClientKind.anthropic:
          await _runAnthropicChat(controller, conversation, userInput,
              attachments, options, route, pageContributors);
        case ProviderClientKind.gemini:
          if (route == ChatRoute.imageGen) {
            await _runImageWithClarification(
                controller, conversation, userInput, pending, 'gemini');
          } else {
            await _runGeminiChat(controller, conversation, userInput,
                attachments, options, route);
          }
        case ProviderClientKind.flux:
          // Flux only serves the image capability, so this is always the
          // image route.
          await _runImageWithClarification(
              controller, conversation, userInput, pending, 'flux');
        case ProviderClientKind.openAiCompatible:
          await _runOpenAiChat(controller, conversation, userInput, attachments,
              options, provider!, model: _autoModelFor(provider, route));
        default:
          // No live provider (video/audio, or an image route without a Gemini
          // key, or no keys at all) → the fully-functional mock.
          await _delegateToMock(controller, conversation, userInput, null,
              attachments, options);
          return;
      }
      await controller.close();
    } catch (e) {
      controller.add(MessageError(e.toString()));
      await controller.close();
    }
  }

  /// Live deep research: the engine's plan/search/synthesize steps run on
  /// whichever provider the user has a key for (Claude preferred).
  Future<void> _runDeepResearch(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String topic,
  ) async {
    controller.add(const RoutingDetected(StudioType.middleware));

    Future<String> completeText(String prompt,
            {bool strongModel = false}) =>
        _completeText(prompt,
            maxTokens: strongModel ? 8000 : 300, strong: strongModel);

    // A grounded (web-search-backed) provider for the search step, if any.
    final searchId =
        chooseProvider(ChatRoute.webSearch, registry: _registry, hasKey: keys.hasKey);

    final engine = DeepResearchEngine(
      planQueries: (topic) async {
        final reply = await completeText(
          'Propose up to 3 focused web-search queries to research this '
          'topic: "$topic". Respond with ONLY a minified JSON array of '
          'strings — no prose, no code fences.',
        );
        try {
          final cleaned =
              reply.replaceAll(RegExp(r'```(json)?'), '').trim();
          return (jsonDecode(cleaned) as List).cast<String>();
        } catch (_) {
          return [topic];
        }
      },
      search: (query) async {
        const ask = 'Search the web and concisely summarize the key '
            'findings for: ';
        // Only Anthropic/Gemini can actually ground on the live web. With just
        // an OpenAI-compatible key, degrade to a plain completion from the
        // model's own knowledge (no live sources) — a documented limitation.
        if (searchId == null) {
          final notes = await _completeText(
            'Concisely summarize what you know about: $query',
            maxTokens: 800,
          );
          return ResearchRoundResult(notes: notes, citations: const []);
        }
        final buffer = StringBuffer();
        final citations = <Citation>[];
        final events = searchId == 'anthropic'
            ? _anthropic.streamChat(
                apiKey: keys.anthropicKey,
                conversation: _emptyConversation(),
                userInput: '$ask$query',
                model: AnthropicApiConfig.sonnetModel,
                tools: const [AnthropicTools.webSearch],
                maxContinuations: 3,
              )
            : _gemini.streamChat(
                apiKey: keys.geminiKey,
                conversation: _emptyConversation(),
                userInput: '$ask$query',
                grounding: true,
              );
        await for (final event in events) {
          if (event is MessageDelta) buffer.write(event.chunk);
          if (event is CitationsReady) citations.addAll(event.citations);
          if (event is MessageError) throw Exception(event.message);
        }
        return ResearchRoundResult(
          notes: buffer.toString(),
          citations: citations,
        );
      },
      synthesize: (topic, notes) => completeText(
        'Write a well-structured markdown research report on "$topic" '
        'from these research notes. Use numbered citation markers like '
        '[1] that correspond to the order sources first appear. Notes:\n\n'
        '$notes',
        strongModel: true,
      ),
    );

    var sawError = false;
    await for (final event
        in engine.run(topic: topic, conversationId: conversation.id)) {
      if (event is MessageError) sawError = true;
      controller.add(event);
    }
    if (!sawError) controller.add(const MessageComplete());
  }

  static Conversation _emptyConversation() => Conversation(
        id: '_research',
        title: '_',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

  /// Copy & Scripts writes the script with a live text model (Claude/Gemini);
  /// the downstream voice/video/music is synthesized locally. The written
  /// script is streamed and also carried on the media result.
  Future<void> _runCopyFedMedia(
    StreamController<ChatEvent> controller,
    CompositionKind kind,
    String userInput,
  ) async {
    controller.add(RoutingDetected(copyFedHost(kind)));
    controller.add(MessageDelta('${copyFedIntro(kind)}\n\n'));

    var script = '';
    try {
      script = (await _writeText(scriptLlmPrompt(kind, userInput))).trim();
    } catch (_) {
      // Fall through to the template below.
    }
    if (script.isEmpty) script = mockScript(kind, userInput);

    controller.add(MessageDelta('$script\n\n'));

    // A scripted video with a Heygen key renders a real talking-avatar clip.
    if (kind == CompositionKind.scriptedVideo) {
      final heygenVideo = await _tryHeygenVideo(script);
      if (heygenVideo != null) {
        controller.add(StudioResultReady(heygenVideo));
        controller.add(const MessageDelta(
            '\n\nRendered with Heygen — open it in a new tab from the card '
            'above.'));
        controller.add(const MessageComplete());
        return;
      }
    }

    controller.add(StudioResultReady(copyFedResult(kind, userInput, script)));
    final followUp = copyFedFollowUp(kind);
    if (followUp.isNotEmpty) controller.add(MessageDelta(followUp));
    controller.add(const MessageComplete());
  }

  /// Renders a real talking-avatar video with Heygen from [script], returning
  /// null when there is no Heygen key or the render fails (so callers fall back
  /// to the simulated card). Represented in the existing [VideoResult] card
  /// with an "Open in Heygen" link and the real thumbnail as the poster.
  Future<VideoResult?> _tryHeygenVideo(String script) async {
    if (!keys.hasKey('heygen')) return null;
    try {
      final video = await _heygen.generateAvatarVideo(
        apiKey: keys.keyFor('heygen'),
        script: script,
      );
      return VideoResult(
        prompt: script,
        durationSec: 10,
        aspectRatio: '16:9',
        identityLock: true,
        seed: StudioResponseBank.seedFromString(script),
        videoUrl: video.videoUrl,
        posterUrl: video.thumbnailUrl,
        providerLabel: 'Heygen',
      );
    } catch (_) {
      return null;
    }
  }

  /// Media pairs (live): a portrait from Gemini (else procedural) shown with
  /// a synthesized voiceover whose script Claude/Gemini actually wrote; or a
  /// narration-over-music-bed card. Voice/music audio is synthesized locally.
  Future<void> _runMediaPair(
    StreamController<ChatEvent> controller,
    CompositionKind kind,
    String userInput,
  ) async {
    controller.add(RoutingDetected(mediaPairHost(kind)));
    controller.add(MessageDelta('${mediaPairIntro(kind)}\n\n'));

    // The voiceover script is written first (real) — both the Heygen render
    // and the synthesized voiceover need it.
    var script = '';
    try {
      script = (await _writeText(scriptLlmPrompt(kind, userInput))).trim();
    } catch (_) {
      // Fall through to the template.
    }
    if (script.isEmpty) script = mockScript(kind, userInput);

    // A talking avatar with a Heygen key becomes a real avatar video (Heygen's
    // core product), shown in the video card instead of the portrait + voice.
    if (kind == CompositionKind.talkingAvatar) {
      final heygenVideo = await _tryHeygenVideo(script);
      if (heygenVideo != null) {
        controller.add(StudioResultReady(heygenVideo));
        controller.add(const MessageDelta(
            '\n\nRendered with Heygen — open it in a new tab from the card '
            'above.'));
        controller.add(const MessageComplete());
        return;
      }
      // No Heygen key (or the render failed): a portrait + synthesized voice.
      final images = keys.hasGeminiKey
          ? await _generateGeminiPhotos('$userInput, portrait headshot', 1)
          : await _generateProceduralPhotos(userInput, 1);
      if (images.isNotEmpty) {
        controller
            .add(ImageGenerated(pngBytes: images.first, alt: 'Avatar portrait'));
      }
    }

    controller.add(StudioResultReady(mediaPairAudio(kind, userInput, script)));
    final followUp = mediaPairFollowUp(kind);
    if (followUp.isNotEmpty) controller.add(MessageDelta(followUp));
    controller.add(const MessageComplete());
  }

  /// Small non-streaming completion on whichever text model the user has a
  /// key for (registry preference order — Claude first, then OpenAI, Gemini,
  /// Groq, Mistral, OpenRouter). [strong] asks for the provider's most capable
  /// model rather than its fast one. Returns '' when no live text provider is
  /// available, so callers fall back to their templates.
  Future<String> _completeText(String prompt,
      {int maxTokens = 400, bool strong = false}) async {
    final id = chooseProvider(ChatRoute.chat, registry: _registry, hasKey: keys.hasKey);
    final provider = id == null ? null : _registry.byId(id);
    switch (provider?.clientKind) {
      case ProviderClientKind.anthropic:
        return _anthropic.complete(
          apiKey: keys.anthropicKey,
          model: strong
              ? AnthropicApiConfig.defaultModel
              : AnthropicApiConfig.haikuModel,
          prompt: prompt,
          maxTokens: maxTokens,
        );
      case ProviderClientKind.gemini:
        return _gemini.complete(
          apiKey: keys.geminiKey,
          prompt: prompt,
          model: strong ? GeminiApiConfig.proModel : GeminiApiConfig.flashModel,
        );
      case ProviderClientKind.openAiCompatible:
        final model = provider!.modelForCapability(ProviderCapability.chat)?.id ??
            provider.defaultModelId ??
            provider.models.first.id;
        return _openAi.complete(
          apiKey: keys.keyFor(provider.id),
          baseUrl: provider.baseUrl!,
          model: model,
          prompt: prompt,
          maxTokens: maxTokens,
          extraHeaders: provider.extraHeaders,
        );
      default:
        return '';
    }
  }

  /// Copy-fed / media-pair scripts write with the best available text model.
  Future<String> _writeText(String prompt) => _completeText(prompt);

  /// Real document translation: the best available text provider translates the
  /// source into the requested language; the result is a downloadable
  /// [TranslateResult]. Degrades to a clearly-labelled simulated result if no
  /// text provider is available or the call fails.
  Future<void> _runTranslate(
      StreamController<ChatEvent> controller, String userInput) async {
    controller.add(const RoutingDetected(StudioType.translateStudio));
    final target = TranslateService.parseTargetLanguage(userInput) ?? 'Spanish';
    final source = TranslateService.extractSourceText(userInput);
    if (source.trim().isEmpty) {
      controller.add(MessageDelta(
          'Happy to translate into $target — what text should I translate?'));
      controller.add(const MessageComplete());
      return;
    }
    controller.add(MessageDelta('Translating into $target…\n\n'));

    var translated = '';
    try {
      translated = (await _completeText(
              TranslateService.translationPrompt(source, target),
              maxTokens: 2000))
          .trim();
    } catch (_) {
      // fall through to the simulated result
    }
    final live = translated.isNotEmpty;
    if (!live) {
      translated = TranslateService.simulatedTranslation(source, target);
    }
    controller.add(StudioResultReady(TranslateResult(
      sourceText: source,
      targetLanguage: target,
      translatedText: translated,
      live: live,
    )));
    controller.add(const MessageComplete());
  }

  Future<void> _runGeminiChat(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    List<Attachment> attachments,
    ChatOptions options,
    ChatRoute route, {
    String? model,
  }) async {
    controller.add(RoutingDetected(route.studioType));
    final events = _gemini.streamChat(
      apiKey: keys.geminiKey,
      conversation: conversation,
      userInput: userInput,
      model: model ?? GeminiApiConfig.flashModel,
      attachments: attachments,
      systemPrompt: options.systemPrompt,
      grounding: options.webSearch || route == ChatRoute.webSearch,
    );
    await controller.addStream(events);
  }

  /// An OpenAI-compatible model (GPT/Groq/OpenRouter/Mistral) answers the turn
  /// directly — whether pinned or chosen by Auto. Plain chat, so no artifact
  /// extraction (mirrors a pinned Claude model).
  Future<void> _runOpenAiChat(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    List<Attachment> attachments,
    ChatOptions options,
    ProviderDescriptor provider, {
    required String model,
  }) async {
    controller.add(RoutingDetected(ChatRoute.chat.studioType));
    final events = _openAi.streamChat(
      apiKey: keys.keyFor(provider.id),
      baseUrl: provider.baseUrl!,
      model: model,
      displayName: _registry.displayNameForModel(model),
      conversation: conversation,
      userInput: userInput,
      attachments: attachments,
      systemPrompt: options.systemPrompt,
      extraHeaders: provider.extraHeaders,
    );
    await controller.addStream(events);
  }

  /// The model an OpenAI-compatible provider should use for an Auto-routed
  /// request: the provider's model for the route's capability, else its default
  /// chat model, else the first listed model.
  String _autoModelFor(ProviderDescriptor provider, ChatRoute route) {
    final capability = capabilityForRoute(route);
    return provider.modelForCapability(capability)?.id ??
        provider.defaultModelId ??
        provider.models.first.id;
  }

  /// The image stream for the chosen image provider (Gemini or Flux). Both map
  /// onto the same ImageGenerated → ImageBlock path.
  Stream<ChatEvent> _imageStream(String providerId, String prompt) {
    if (providerId == 'flux') {
      return _flux.generateImage(apiKey: keys.keyFor('flux'), prompt: prompt);
    }
    return _gemini.generateImage(apiKey: keys.geminiKey, prompt: prompt);
  }

  String _imageProviderName(String providerId) =>
      providerId == 'flux' ? 'Flux' : 'Gemini';

  /// Freeform image prompts get the same "ask before guessing" gate as the
  /// mock — the image endpoints are one-shot (no conversation), so this is the
  /// only chance to ask before spending a real generation call. Works for any
  /// image provider ([providerId] = 'gemini' or 'flux').
  Future<void> _runImageWithClarification(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    (StudioType, String)? pending,
    String providerId,
  ) async {
    controller.add(const RoutingDetected(StudioType.imageStudio));
    if (pending == null) {
      final question = StudioResponseBank.clarifyingQuestion(
          StudioType.imageStudio, userInput);
      if (question != null) {
        controller.add(MessageDelta(question));
        controller.add(const MessageComplete());
        return;
      }
    }
    final effectiveInput =
        pending != null ? '${pending.$2} $userInput'.trim() : userInput;

    // "Add a hero image to the website": the image provider generates the
    // asset, then it's spliced into the artifact a prior turn already built —
    // two studios composing within one turn.
    final composeTarget =
        findArtifactCompositionTarget(conversation, effectiveInput);
    if (composeTarget != null) {
      await _composeImageIntoArtifact(
          controller, providerId, composeTarget, effectiveInput);
      return;
    }

    await _runImage(controller, providerId, effectiveInput, close: false);
  }

  /// Generates the image with the chosen provider, then splices the bytes into
  /// [target]'s HTML as a new artifact version instead of showing them as a
  /// separate inline image.
  Future<void> _composeImageIntoArtifact(
    StreamController<ChatEvent> controller,
    String providerId,
    Artifact target,
    String prompt,
  ) async {
    controller.add(MessageDelta(
        'Generating the image with ${_imageProviderName(providerId)}, then '
        'adding it into "${target.title}"…\n\n'));
    Uint8List? bytes;
    await for (final event in _imageStream(providerId, prompt)) {
      switch (event) {
        case ImageGenerated(:final pngBytes):
          bytes = pngBytes;
        case MessageComplete():
          break; // re-added below, after the artifact update
        default:
          controller.add(event);
      }
    }
    if (bytes == null) return; // an error was already forwarded above
    final updatedHtml =
        embedImageAsHero(target.latest.content, bytes, altText: prompt);
    controller
        .add(ArtifactUpdated(target.withNewVersion(updatedHtml, DateTime.now())));
    controller.add(MessageDelta(
        '\n\nDone — it\'s live in "${target.title}" as a new version.'));
    controller.add(const MessageComplete());
  }

  Future<void> _runImage(
    StreamController<ChatEvent> controller,
    String providerId,
    String prompt, {
    bool close = true,
  }) async {
    if (close) {
      controller.add(RoutingDetected(ChatRoute.imageGen.studioType));
    }
    controller.add(MessageDelta(
        'Routing this to Image Studio — generating with '
        '${_imageProviderName(providerId)}…\n\n'));
    await controller.addStream(_imageStream(providerId, prompt));
    if (close) await controller.close();
  }

  Future<void> _delegateToMock(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    StudioRequest? structuredRequest,
    List<Attachment> attachments,
    ChatOptions options,
  ) async {
    final stream = _mockFallback.sendMessage(
      conversation: conversation,
      userInput: userInput,
      structuredRequest: structuredRequest,
      attachments: attachments,
      options: options,
    );
    await controller.addStream(stream);
    await controller.close();
  }

  Future<void> _runAnthropicChat(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    List<Attachment> attachments,
    ChatOptions options,
    ChatRoute route,
    Set<StudioType> pageContributors,
  ) async {
    controller.add(RoutingDetected(route.studioType));

    final model = options.modelPin ?? AnthropicApiConfig.defaultModel;
    final buffer = StringBuffer();
    var failed = false;

    // Server tools: explicit composer toggles, plus web search whenever the
    // router decided the prompt needs fresh information.
    final tools = <Map<String, dynamic>>[
      if (options.webSearch || route == ChatRoute.webSearch)
        AnthropicTools.webSearch,
      if (options.codeExecution) AnthropicTools.codeExecution,
    ];

    final events = _anthropic.streamChat(
      apiKey: keys.anthropicKey,
      conversation: conversation,
      userInput: userInput,
      model: model,
      attachments: attachments,
      systemPrompt: options.systemPrompt,
      tools: tools,
    );

    await for (final event in events) {
      if (event is MessageDelta) buffer.write(event.chunk);
      if (event is MessageError) failed = true;
      if (event is MessageComplete && !failed) {
        // Code-routed replies whose fenced block is substantial also become
        // an artifact, mirroring the mock's behavior.
        if (route == ChatRoute.code) {
          var artifact =
              extractCodeArtifact(buffer.toString(), conversation.id);
          if (artifact != null) {
            if (pageContributors.isNotEmpty &&
                artifact.kind == ArtifactKind.html) {
              // Claude built the page; now the other studios supply its
              // photos, soundtrack/voiceover, and video — woven in before
              // the artifact ever reaches the UI, all contributing to the
              // one turn. (Copy is already Claude's own on the page.)
              artifact = await _assembleContributions(
                  artifact, userInput, pageContributors);
            }
            controller.add(ArtifactCreated(artifact));
          }
        }
      }
      controller.add(event);
    }
  }

  /// Weaves each contributor studio's output into a freshly built HTML page:
  /// photos (real Gemini when a Google key exists, else the same procedural
  /// art the mock uses, so the page is never left without visuals), a
  /// synthesized soundtrack/voiceover player, and a video block. Copy is not
  /// embedded here — the live model wrote the page's own copy. Inserted in
  /// reverse display order so the page reads gallery -> audio -> video.
  Future<Artifact> _assembleContributions(
    Artifact artifact,
    String userInput,
    Set<StudioType> contributors,
  ) async {
    final seed = StudioResponseBank.seedFromString(userInput);
    var html = artifact.latest.content;

    if (contributors.contains(StudioType.videoStudio)) {
      final poster = await rasterizeGradientArt(seed: seed + 100);
      html = embedVideoBlock(html, poster, label: userInput);
    }
    if (contributors.contains(StudioType.musicStudio)) {
      html = embedAudioPlayer(
        html,
        AudioSynthService.synthesizeWav(
            seed: seed, durationSec: 20, bpm: 100, speechLike: false),
        label: 'Soundtrack',
      );
    } else if (contributors.contains(StudioType.voiceAvatarStudio)) {
      html = embedAudioPlayer(
        html,
        AudioSynthService.synthesizeWav(
            seed: seed, durationSec: 8, bpm: 100, speechLike: true),
        label: 'Voiceover',
      );
    }
    if (contributors.contains(StudioType.imageStudio)) {
      final count = photoCountHint(userInput);
      final images = keys.hasGeminiKey
          ? await _generateGeminiPhotos(userInput, count)
          : await _generateProceduralPhotos(userInput, count);
      if (images.isNotEmpty) {
        html = embedImageGallery(html, images, altText: userInput);
      }
    }

    return Artifact(
      id: artifact.id,
      conversationId: artifact.conversationId,
      title: artifact.title,
      kind: artifact.kind,
      language: artifact.language,
      versions: [ArtifactVersion(content: html, createdAt: DateTime.now())],
    );
  }

  Future<List<Uint8List>> _generateGeminiPhotos(
      String prompt, int count) async {
    final images = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      await for (final event
          in _gemini.generateImage(apiKey: keys.geminiKey, prompt: prompt)) {
        if (event is ImageGenerated) images.add(event.pngBytes);
      }
    }
    return images;
  }

  Future<List<Uint8List>> _generateProceduralPhotos(
      String prompt, int count) async {
    final seed = StudioResponseBank.seedFromString(prompt);
    return Future.wait([
      for (var i = 0; i < count; i++) rasterizeGradientArt(seed: seed + i),
    ]);
  }

  /// Pulls the first substantial fenced code block out of a completed reply
  /// as an artifact. Returns null when there's nothing artifact-worthy.
  static Artifact? extractCodeArtifact(String text, String conversationId) {
    final match =
        RegExp(r'```([A-Za-z0-9+#_-]*)\n([\s\S]*?)```').firstMatch(text);
    if (match == null) return null;
    final code = match.group(2)!.trim();
    if (code.split('\n').length < 5) return null;
    final language = match.group(1)!.toLowerCase();
    final isHtml = language == 'html' || code.startsWith('<!DOCTYPE');
    return Artifact(
      id: _uuid.v4(),
      conversationId: conversationId,
      title: isHtml ? 'Generated page' : 'Generated ${language.isEmpty ? 'code' : language}',
      kind: isHtml ? ArtifactKind.html : ArtifactKind.code,
      language: language.isEmpty ? null : language,
      versions: [ArtifactVersion(content: code, createdAt: DateTime.now())],
    );
  }
}

/// The single seam the UI talks to: picks the live service when the user
/// has added a key, the mock otherwise — per message, so adding or removing
/// a key in Settings takes effect immediately with zero UI branching.
class ChatServiceSelector implements ChatService {
  final ApiKeysStore keys;
  final ChatService real;
  final ChatService mock;

  ChatServiceSelector({
    required this.keys,
    required this.real,
    required this.mock,
  });

  @override
  Stream<ChatEvent> sendMessage({
    required Conversation conversation,
    required String userInput,
    StudioRequest? structuredRequest,
    List<Attachment> attachments = const [],
    ChatOptions options = ChatOptions.none,
  }) {
    final service = keys.isLive ? real : mock;
    return service.sendMessage(
      conversation: conversation,
      userInput: userInput,
      structuredRequest: structuredRequest,
      attachments: attachments,
      options: options,
    );
  }
}
