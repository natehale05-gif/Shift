import '../../features/artifacts/interactive/interactive_render.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../data/models/artifact.dart';
import '../../data/models/attachment.dart';
import '../../data/models/citation.dart';
import '../../data/models/conversation.dart';
import '../../data/models/studio_request.dart';
import '../../data/models/studio_result.dart';
import '../../data/models/studio_type.dart';
import '../../data/stores/api_keys_store.dart';
import '../../features/artifacts/artifact_composition.dart';
import '../request_title.dart';
import '../studio_detection.dart';
import '../../features/studios/media/audio_synth_service.dart';
import '../chat_service.dart';
import '../turn_plan.dart';
import '../turn_input.dart';
import '../plan_turn.dart';
import '../prompt_assembler.dart';
import '../deep_research_engine.dart';
import 'mock_backend.dart';
import '../../features/studios/media/procedural_art.dart';
import '../../features/studios/brand_pack/brand_pack_service.dart';
import '../../features/studios/deck/deck_service.dart';
import '../../features/artifacts/interactive/interactive_content.dart';
import '../../features/studios/short_reels/short_reels_service.dart';
import '../studio_composition.dart';
import '../../features/studios/translate/translate_service.dart';
import '../../providers/clients/anthropic_api_config.dart';
import '../../providers/clients/anthropic_client.dart';
import '../../providers/clients/anthropic_tools.dart';
import '../../providers/clients/flux_client.dart';
import '../../providers/clients/gemini_api_config.dart';
import '../../providers/clients/gemini_client.dart';
import '../../providers/clients/heygen_client.dart';
import '../../providers/clients/openai_compatible_client.dart';
import '../../providers/clients/provider_capability.dart';
import '../../providers/clients/provider_descriptor.dart';
import '../../providers/clients/provider_registry.dart';
import '../../providers/router/model_router.dart';
import '../../providers/router/provider_selection.dart';
import '../../features/studios/studio_response_bank.dart';

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
      // One decision for the turn, made by the same pure function the demo
      // backend uses. Live and simulated answers now differ only in how a plan
      // is *performed*, never in what the plan is.
      final turn = planTurn(TurnInput(
        conversation: conversation,
        userInput: userInput,
        structuredRequest: structuredRequest,
        attachments: attachments,
        options: options,
      ));

      switch (turn) {
        case InteractiveTurn(:final kind):
          await _runInteractive(controller, conversation, kind, userInput);
          await controller.close();
          return;

        case DeepResearchTurn():
          // Nothing to research with if the user has no keys at all.
          if (keys.isLive) {
            await _runDeepResearch(controller, conversation, userInput);
          } else {
            await _delegateToMock(controller, conversation, userInput, null,
                attachments, options);
            return;
          }
          await controller.close();
          return;

        case CopyFedTurn(:final kind):
          await _runCopyFedMedia(controller, kind, turn.effectiveInput);
          await controller.close();
          return;

        case MediaPairTurn(:final kind):
          await _runMediaPair(controller, kind, turn.effectiveInput,
              studio: turn.studio == StudioType.avatarStudio
                  ? StudioType.avatarStudio
                  : null);
          await controller.close();
          return;

        // A diagram or a grounded question is just a chat turn for a live
        // model — it writes its own mermaid, and web search is a tool on the
        // normal chat path. Both fall through to the routing tail below.
        case DiagramTurn():
        case WebSearchTurn():
        case StudioTurn():
          break;
      }

      // A structured studio form runs real generation only for images with a
      // key; every other form still has a simulated executor.
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

      // "Add background music / a video to the website": audio and video are
      // always synthesized (no live provider), so the mock performs the embed
      // into the existing artifact. Image edits keep the live image path
      // below (Gemini/Flux, or the mock when no image key exists).
      if (turn is StudioTurn &&
          turn.composeTarget != null &&
          turn.composeKind != ArtifactMediaKind.image) {
        await _delegateToMock(
            controller, conversation, userInput, null, attachments, options);
        return;
      }

      final wantsBoth =
          turn is StudioTurn && turn.contributors.isNotEmpty;

      // An explicit model pin bypasses studio routing and dispatches to the
      // pinned model's provider (as long as the user has that key). Claude
      // pins fall through to the existing Anthropic path below, which already
      // reads options.modelPin.
      //
      // A pin says *which model* answers, not *what kind of answer* it is.
      // Pinning must not hand the turn to Image Studio — but a page or code
      // request still has to produce an artifact, so the pinned turn picks
      // between the two routes a text model can actually serve. It used to be
      // hardcoded to chat, which silently dropped the deliverable and left a
      // fenced block in the message.
      final pin = options.modelPin;
      final pinnedRoute =
          StudioDetection.detectStudio(userInput) == StudioType.codeStudio
              ? ChatRoute.code
              : ChatRoute.chat;
      if (pin != null) {
        final provider = _registry.providerForModel(pin);
        if (provider != null && keys.hasKey(provider.id)) {
          final reviseTarget =
              turn is StudioTurn ? turn.reviseTarget : null;
          if (provider.clientKind == ProviderClientKind.openAiCompatible) {
            await _runOpenAiChat(controller, conversation, userInput,
                attachments, options, provider,
                model: pin, route: pinnedRoute, reviseTarget: reviseTarget);
            await controller.close();
            return;
          }
          if (provider.id == 'gemini') {
            await _runGeminiChat(controller, conversation, userInput,
                attachments, options, pinnedRoute,
                model: pin, reviseTarget: reviseTarget);
            await controller.close();
            return;
          }
        }
      }

      final route = pin != null
          ? pinnedRoute
          : turn.isAnsweringClarification
              ? routeForStudio(turn.studio)
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

      // Deck is a real deliverable: the best text provider writes the outline,
      // returned as a downloadable .pptx (DeckResult) + an HTML deck artifact.
      if (route == ChatRoute.deck) {
        await _runDeck(controller, conversation, userInput);
        await controller.close();
        return;
      }

      // Brand Pack is a real deliverable: a logo (real image provider when
      // keyed, else procedural), a palette and a type pairing, downloadable as
      // a .zip kit.
      if (route == ChatRoute.brandPack) {
        await _runBrandPack(controller, userInput);
        await controller.close();
        return;
      }

      // ShortReels is a real deliverable: a pack of short-form reels (hooks +
      // scripts written by the best text provider, procedural posters),
      // downloadable as a .zip.
      if (route == ChatRoute.shortReels) {
        await _runShortReels(controller, userInput);
        await controller.close();
        return;
      }

      // Avatar = a talking-head video: a real Heygen render when a Heygen key
      // exists, else a portrait + synthesized voiceover. Reuses the
      // talking-avatar media-pair path, attributed to the Avatar studio.
      if (route == ChatRoute.avatar) {
        await _runMediaPair(controller, CompositionKind.talkingAvatar, userInput,
            studio: StudioType.avatarStudio);
        await controller.close();
        return;
      }

      // Auto: pick the best available provider for the route's capability.
      final providerId =
          chooseProvider(route, registry: _registry, hasKey: keys.hasKey);
      final provider = providerId == null ? null : _registry.byId(providerId);

      final pageContributors =
          turn is StudioTurn ? turn.contributors : const <StudioType>{};
      final reviseTarget = turn is StudioTurn ? turn.reviseTarget : null;

      switch (provider?.clientKind) {
        case ProviderClientKind.anthropic:
          await _runAnthropicChat(controller, conversation, userInput,
              attachments, options, route, pageContributors, reviseTarget);
        case ProviderClientKind.gemini:
          if (route == ChatRoute.imageGen) {
            await _runImageWithClarification(controller, conversation,
                userInput, turn.effectiveInput,
                turn.isAnsweringClarification, 'gemini');
          } else {
            await _runGeminiChat(controller, conversation, userInput,
                attachments, options, route,
                pageContributors: pageContributors,
                reviseTarget: reviseTarget);
          }
        case ProviderClientKind.flux:
          // Flux only serves the image capability, so this is always the
          // image route.
          await _runImageWithClarification(controller, conversation, userInput,
              turn.effectiveInput, turn.isAnsweringClarification, 'flux');
        case ProviderClientKind.openAiCompatible:
          await _runOpenAiChat(controller, conversation, userInput, attachments,
              options, provider!,
              model: _autoModelFor(provider, route),
              route: route,
              pageContributors: pageContributors,
              reviseTarget: reviseTarget);
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
            '\n\nRendered — open it in a new tab from the card '
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
    String userInput, {
    StudioType? studio,
  }) async {
    controller.add(RoutingDetected(studio ?? mediaPairHost(kind)));
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
            '\n\nRendered — open it in a new tab from the card '
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

  /// Real slide deck: the best text provider writes a JSON outline, rendered as
  /// a downloadable .pptx (DeckResult) and an HTML deck artifact. Falls back to
  /// a templated outline when no provider is available or the call fails.
  Future<void> _runDeck(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
  ) async {
    controller.add(const RoutingDetected(StudioType.deckStudio));
    final req = DeckService.parseDeckRequest(userInput);
    controller.add(MessageDelta(
        'Building a ${req.slideCount}-slide deck on "${req.topic}"…\n\n'));

    DeckResult? deck;
    try {
      final reply = await _completeText(
          DeckService.outlinePrompt(req.topic, req.slideCount),
          maxTokens: 2000);
      deck = DeckService.parseOutlineJson(reply, req.topic);
    } catch (_) {
      // fall through to the template
    }
    deck ??= DeckService.templatedDeck(req.topic, req.slideCount);

    controller.add(ArtifactCreated(Artifact(
      id: _uuid.v4(),
      conversationId: conversation.id,
      title: '${deck.title} — deck',
      kind: ArtifactKind.html,
      versions: [
        ArtifactVersion(
            content: DeckService.buildDeckHtml(deck), createdAt: DateTime.now()),
      ],
    )));
    controller.add(StudioResultReady(deck));
    controller.add(const MessageComplete());
  }

  /// Real brand pack: a logo (best image provider when keyed, else procedural),
  /// a deterministic palette + type pairing, emitted as a BrandPackResult whose
  /// card downloads a .zip kit.
  Future<void> _runBrandPack(
      StreamController<ChatEvent> controller, String userInput) async {
    controller.add(const RoutingDetected(StudioType.brandPackStudio));
    final name = BrandPackService.parseBrandName(userInput);
    controller.add(MessageDelta('Designing a brand pack for "$name"…\n\n'));
    final seed = BrandPackService.seedFor(name);

    Uint8List? logo;
    final imageId =
        chooseProvider(ChatRoute.imageGen, registry: _registry, hasKey: keys.hasKey);
    if (imageId != null) {
      try {
        await for (final event in _imageStream(imageId,
            '$name logo, minimalist flat vector mark, on a white background')) {
          if (event is ImageGenerated) {
            logo = event.pngBytes;
            break;
          }
        }
      } catch (_) {
        // fall through to procedural
      }
    }
    final providerLogo = logo != null;
    logo ??= await rasterizeGradientArt(seed: seed);

    final fonts = BrandPackService.fontPair(seed);
    controller.add(StudioResultReady(BrandPackResult(
      brandName: name,
      palette: BrandPackService.buildPalette(seed),
      headingFont: fonts.heading,
      bodyFont: fonts.body,
      seed: seed,
      live: providerLogo,
      logoPng: logo,
    )));
    controller.add(const MessageComplete());
  }

  /// Interactive artifact (recipe card / quiz / flashcards / checklist): the
  /// best text provider fills the real content; Image Studio can supply a hero
  /// photo for recipes. Falls back to templated content when no text provider
  /// is available. Emitted as a runnable HTML artifact.
  Future<void> _runInteractive(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    InteractiveKind kind,
    String userInput,
  ) async {
    controller.add(const RoutingDetected(StudioType.codeStudio));
    final topic = InteractiveArtifacts.parseTopic(userInput, kind);
    controller.add(
        MessageDelta('Building an interactive ${kind.label} for "$topic"…\n\n'));

    String reply = '';
    try {
      reply = await _completeText(
          InteractiveArtifacts.contentPrompt(kind, topic),
          maxTokens: 2000);
    } catch (_) {
      // fall through to templated content
    }

    // A hero photo for recipes when the prompt asks for one or an image
    // provider is available (Image Studio contributing to Code Studio's widget).
    String? heroUri;
    if (kind == InteractiveKind.recipe) {
      final imageId = chooseProvider(ChatRoute.imageGen,
          registry: _registry, hasKey: keys.hasKey);
      final wantsPhoto = _mentionsPhoto(userInput) || imageId != null;
      if (wantsPhoto) {
        Uint8List? bytes;
        if (imageId != null) {
          try {
            await for (final event in _imageStream(
                imageId, '$topic, appetizing food photography, on a plate')) {
              if (event is ImageGenerated) {
                bytes = event.pngBytes;
                break;
              }
            }
          } catch (_) {/* procedural fallback below */}
        }
        bytes ??= await rasterizeGradientArt(
            seed: StudioResponseBank.seedFromString(topic));
        heroUri = 'data:image/png;base64,${base64Encode(bytes)}';
      }
    }

    final (html, title, live) =
        _renderInteractive(kind, reply, topic, heroUri);
    controller.add(ArtifactCreated(InteractiveRender.build(
      kind: kind,
      conversationId: conversation.id,
      title: title,
      html: html,
    )));
    controller.add(MessageDelta(live
        ? '\n\nIt\'s live and interactive right here in the chat — try it out.'
        : '\n\nIt\'s interactive right here in the chat. (Add a key with more '
            'context and I\'ll write richer content.)'));
    controller.add(const MessageComplete());
  }

  static bool _mentionsPhoto(String input) {
    final lower = input.toLowerCase();
    return lower.contains('photo') ||
        lower.contains('image') ||
        lower.contains('picture') ||
        lower.contains('with a pic');
  }

  /// Parses the provider [reply] for [kind] (falling back to templated
  /// content) and renders the interactive HTML. Returns (html, title, live).
  (String, String, bool) _renderInteractive(
      InteractiveKind kind, String reply, String topic, String? heroUri) {
    final t = _titleCase(topic);
    switch (kind) {
      case InteractiveKind.recipe:
        final parsed = InteractiveArtifacts.parseRecipeJson(reply, topic);
        final recipe = parsed ?? InteractiveArtifacts.templatedRecipe(topic);
        return (
          InteractiveRender.renderRecipe(recipe, heroImageDataUri: heroUri),
          recipe.title,
          parsed != null,
        );
      case InteractiveKind.quiz:
        final parsed = InteractiveArtifacts.parseQuizJson(reply);
        final qs = parsed ?? InteractiveArtifacts.templatedQuiz(topic);
        return (InteractiveRender.renderQuiz(qs, '$t Quiz'), '$t Quiz',
            parsed != null);
      case InteractiveKind.flashcards:
        final parsed = InteractiveArtifacts.parseFlashcardsJson(reply);
        final cards = parsed ?? InteractiveArtifacts.templatedFlashcards(topic);
        return (
          InteractiveRender.renderFlashcards(cards, '$t Flashcards'),
          '$t Flashcards',
          parsed != null
        );
      case InteractiveKind.checklist:
        final parsed = InteractiveArtifacts.parseChecklistJson(reply);
        final items = parsed ?? InteractiveArtifacts.templatedChecklist(topic);
        return (InteractiveRender.renderChecklist(items, t), t,
            parsed != null);
    }
  }

  static String _titleCase(String s) => s.isEmpty
      ? s
      : s
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join(' ');

  /// Real short-form pack: the best text provider writes the hooks + scripts;
  /// posters are procedural (regenerated from each reel's seed). Downloadable
  /// as a .zip. Falls back to a templated pack when no provider is available.
  Future<void> _runShortReels(
      StreamController<ChatEvent> controller, String userInput) async {
    controller.add(const RoutingDetected(StudioType.shortReelsStudio));
    final req = ShortReelsService.parseReelsRequest(userInput);
    controller.add(MessageDelta(
        'Cutting a ${req.count}-reel pack on "${req.topic}"…\n\n'));

    ShortReelsPackResult? pack;
    try {
      final reply = await _completeText(
          ShortReelsService.scriptsPrompt(req.topic, req.count),
          maxTokens: 2000);
      pack = ShortReelsService.parsePackJson(reply, req.topic);
    } catch (_) {
      // fall through to the template
    }
    pack ??= ShortReelsService.templatedPack(req.topic, req.count);

    controller.add(StudioResultReady(pack));
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
    Set<StudioType> pageContributors = const {},
    Artifact? reviseTarget,
  }) async {
    controller.add(RoutingDetected(route.studioType));
    final events = _gemini.streamChat(
      apiKey: keys.geminiKey,
      conversation: conversation,
      userInput: userInput,
      model: model ?? GeminiApiConfig.flashModel,
      attachments: attachments,
      systemPrompt: systemPromptForCodeTurn(options.systemPrompt,
          isCode: route == ChatRoute.code),
      grounding: options.webSearch || route == ChatRoute.webSearch,
    );
    await _streamText(
      controller,
      events,
      conversation: conversation,
      userInput: userInput,
      route: route,
      pageContributors: pageContributors,
      reviseTarget: reviseTarget,
    );
  }

  /// An OpenAI-compatible model (GPT/Groq/OpenRouter/Mistral) answers the turn
  /// directly — whether pinned or chosen by Auto. A code-routed turn yields an
  /// artifact just as Claude's does; a pin forces the chat route, so pinned
  /// models still answer inline.
  Future<void> _runOpenAiChat(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    List<Attachment> attachments,
    ChatOptions options,
    ProviderDescriptor provider, {
    required String model,
    ChatRoute route = ChatRoute.chat,
    Set<StudioType> pageContributors = const {},
    Artifact? reviseTarget,
  }) async {
    controller.add(RoutingDetected(route.studioType));
    final events = _openAi.streamChat(
      apiKey: keys.keyFor(provider.id),
      baseUrl: provider.baseUrl!,
      model: model,
      displayName: _registry.displayNameForModel(model),
      conversation: conversation,
      userInput: userInput,
      attachments: attachments,
      systemPrompt: systemPromptForCodeTurn(options.systemPrompt,
          isCode: route == ChatRoute.code),
      extraHeaders: provider.extraHeaders,
    );
    await _streamText(
      controller,
      events,
      conversation: conversation,
      userInput: userInput,
      route: route,
      pageContributors: pageContributors,
      reviseTarget: reviseTarget,
    );
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

  /// Freeform image prompts get the same "ask before guessing" gate as the
  /// mock — the image endpoints are one-shot (no conversation), so this is the
  /// only chance to ask before spending a real generation call. Works for any
  /// image provider ([providerId] = 'gemini' or 'flux').
  Future<void> _runImageWithClarification(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    String effectiveInput,
    bool isAnsweringClarification,
    String providerId,
  ) async {
    controller.add(const RoutingDetected(StudioType.imageStudio));
    // Ask before guessing — but never twice: an answer to our own question
    // proceeds straight to generating. The merge of question-and-answer was
    // already done by planTurn, which is why effectiveInput arrives ready.
    if (!isAnsweringClarification) {
      final question = StudioResponseBank.clarifyingQuestion(
          StudioType.imageStudio, userInput);
      if (question != null) {
        controller.add(MessageDelta(question));
        controller.add(const MessageComplete());
        return;
      }
    }

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
        'Adding an image to "${target.title}"…\n\n'));
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
    controller.add(const MessageDelta('Creating that image…\n\n'));
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
    Artifact? reviseTarget,
  ) async {
    controller.add(RoutingDetected(route.studioType));

    final model = options.modelPin ?? AnthropicApiConfig.defaultModel;

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
      systemPrompt: systemPromptForCodeTurn(options.systemPrompt,
          isCode: route == ChatRoute.code),
      tools: tools,
      extendedThinking: options.extendedThinking,
    );

    await _streamText(
      controller,
      events,
      conversation: conversation,
      userInput: userInput,
      route: route,
      pageContributors: pageContributors,
      reviseTarget: reviseTarget,
    );
  }

  /// Pipes a text provider's events to the UI, and on a code-routed turn turns
  /// the completed reply's fenced block into an artifact.
  ///
  /// Shared by every text client — Claude, Gemini and the OpenAI-compatible
  /// providers — because which model wrote the page has no bearing on how the
  /// page becomes an artifact. Only Claude used to do this, so a user whose
  /// key was for anything else got prose with a code fence in it and an empty
  /// side panel.
  Future<void> _streamText(
    StreamController<ChatEvent> controller,
    Stream<ChatEvent> events, {
    required Conversation conversation,
    required String userInput,
    required ChatRoute route,
    Set<StudioType> pageContributors = const {},
    Artifact? reviseTarget,
  }) async {
    final buffer = StringBuffer();
    var failed = false;

    await for (final event in events) {
      if (event is MessageDelta) buffer.write(event.chunk);
      if (event is MessageError) failed = true;
      if (event is MessageComplete && !failed) {
        // Code-routed replies whose fenced block is substantial also become
        // an artifact, mirroring the mock's behavior. (A model pin forces the
        // chat route, so pinned models deliberately produce no artifact.)
        if (route == ChatRoute.code) {
          var artifact = extractCodeArtifact(
              buffer.toString(), conversation.id,
              title: titleFromRequest(userInput));
          if (artifact != null) {
            if (pageContributors.isNotEmpty &&
                artifact.kind == ArtifactKind.html) {
              // The model built the page; now the other studios supply its
              // photos, soundtrack/voiceover, and video — woven in before
              // the artifact ever reaches the UI, all contributing to the
              // one turn. (Copy is already the model's own on the page.)
              artifact = await _assembleContributions(
                  artifact, userInput, pageContributors);
            }
            // A revision keeps the user's artifact and gains a version, so the
            // panel's version navigator can step back to what it replaced —
            // rather than leaving two near-identical artifacts side by side.
            if (reviseTarget != null && reviseTarget.kind == artifact.kind) {
              controller.add(ArtifactUpdated(reviseTarget.withNewVersion(
                  artifact.latest.content, DateTime.now())));
            } else {
              controller.add(ArtifactCreated(artifact));
            }
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
  ///
  /// [title] names the result. Without it every artifact was called "Generated
  /// page", which is also the download filename — so a second download
  /// collided with the first and the sidebar showed a column of identical
  /// names.
  static Artifact? extractCodeArtifact(
    String text,
    String conversationId, {
    String? title,
  }) {
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
      title: title ??
          (isHtml
              ? 'Generated page'
              : 'Generated ${language.isEmpty ? 'code' : language}'),
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
