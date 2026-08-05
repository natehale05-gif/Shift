import 'package:flutter/foundation.dart';
import '../../features/artifacts/interactive/interactive_render.dart';
import 'dart:async';
import 'dart:math' show max;
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../data/models/artifact.dart';
import '../../data/models/attachment.dart';
import '../../data/models/citation.dart';
import '../../data/models/conversation.dart';
import '../../data/models/studio_request.dart';
import '../../data/models/studio_result.dart';
import '../../data/models/studio_type.dart';
import '../../data/stores/api_keys_store.dart';
import '../../providers/clients/provider_access.dart';
import '../../features/artifacts/artifact_composition.dart';
import '../conversation_media.dart';
import '../choice_parsing.dart';
import '../fence_filter.dart';
import '../request_title.dart';
import '../studio_detection.dart';
import '../../features/studios/media/audio_synth_service.dart';
import '../../providers/clients/provider_error.dart';
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
import '../../providers/clients/openai_image_client.dart';
import '../../providers/clients/openai_video_client.dart';
import '../../providers/clients/elevenlabs_client.dart';
import '../../providers/clients/fal_client.dart';
import '../../providers/clients/replicate_client.dart';
import '../../providers/streaming/sse_client.dart';
import '../../providers/clients/provider_capability.dart';
import '../../providers/clients/provider_descriptor.dart';
import '../../providers/clients/provider_registry.dart';
import '../../providers/clients/proxyable_providers.dart';
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

/// The tool id and name the backend reports while a fenced deliverable is
/// being written.
///
/// It rides on the existing tool-use events rather than a new kind of event:
/// message folding, persistence and the running/done lifecycle already work,
/// and the UI only has to know that this one tool draws as the build animation
/// instead of a chip.
const String writingToolId = 'shift-writing';
const String writingToolName = 'shift_write';

/// Whether this turn is asking for speech rather than a score.
///
/// [ChatRoute.voice] always is. [ChatRoute.audio] is shared between Music and
/// Voice Studio, so the wording decides — "generate audio talking about pink
/// flowers" wants a voice, "an audio bed for my ad" wants music.
///
/// Pure, so the one sentence that decides whether a paid voice key is used at
/// all can be asserted directly.
bool _wantsSpokenAudio(ChatRoute route, String userInput) =>
    route == ChatRoute.voice ||
    (route == ChatRoute.audio &&
        StudioDetection.detectStudio(userInput) == StudioType.voiceStudio);

@visibleForTesting
bool wantsSpokenAudio(ChatRoute route, String userInput) =>
    _wantsSpokenAudio(route, userInput);

/// The brief a voiceover turn hands the text provider.
///
/// "A voiceover talking about pink flowers" is a brief, not a line to read
/// aloud — speaking the prompt back verbatim would be the wrong deliverable.
String voiceScriptPrompt(String userInput) =>
    'Write the words to be spoken aloud for this request: "$userInput".\n\n'
    'Return only the script — no title, no stage directions, no speaker '
    'labels, no quotation marks around it. Around 60-90 words, written to be '
    'heard rather than read.';

/// The script demo mode reads when no text provider answered.
String mockVoiceScript(String userInput) =>
    'Here is a short piece about ${userInput.trim()}. '
    'This is the built-in synthesizer standing in for a real voice — add a '
    'voice provider key in Settings and the same script comes back spoken.';

/// A readable reason a voice call failed, from the status alone.
///
/// The same shape as `heygenProblem`: the point is that the user learns
/// whether it was the key, the plan or the request, rather than being handed a
/// synthesized card in silence.
String elevenLabsProblem(int statusCode, String body) => switch (statusCode) {
      401 || 403 =>
        'ElevenLabs rejected the key, so this is the built-in synthesizer. '
            'Check it in Settings.',
      422 => 'ElevenLabs could not read that request, so this is the built-in '
          'synthesizer.',
      429 => 'ElevenLabs is rate-limiting or the character quota is used up, '
          'so this is the built-in synthesizer.',
      _ => 'ElevenLabs returned $statusCode, so this is the built-in '
          'synthesizer.',
    };

/// Live-mode middleware: routes each message (LLM classifier with keyword
/// fallback), then executes on the best available provider. Routes no live
/// provider can serve yet (image/video/audio before a Gemini key exists)
/// fall back to the mock so the request still produces a useful, clearly
/// simulated result.
class RealChatService implements ChatService {
  final ApiKeysStore keys;

  /// Providers a membership currently covers, answered synchronously because
  /// [chooseProvider] has to decide before anything is awaited. Cached by
  /// `AccountStore` and refreshed on sign-in; empty when signed out.
  ///
  /// This is the line that makes the whole arrangement work. Without it a
  /// member with a plan and no keys of their own has `hasKey` false
  /// everywhere, so routing picks nobody and the turn falls back to the mock
  /// before any of the managed path is reached.
  final Set<String> Function() _managedProviders;

  /// Where a managed call for a provider goes, with a freshly refreshed token.
  /// Null when this account cannot spend one.
  final Future<ProviderAccess?> Function(String provider)? _managedAccess;

  final AnthropicClient _anthropic;
  final GeminiClient _gemini;
  final OpenAiCompatibleClient _openAi;
  final OpenAiImageClient _openAiImages;
  final FluxClient _flux;
  final ReplicateClient _replicate;
  final FalClient _fal;
  final ElevenLabsClient _elevenLabs;
  final HeygenClient _heygen;
  final OpenAiVideoClient _openAiVideo;
  final ProviderRegistry _registry;
  final ModelRouter _router;
  final MockChatService _mockFallback;

  /// Reads a stored asset's bytes. Supplied by the app so a picture generated
  /// in an earlier session — whose in-memory bytes are long gone — can still
  /// be put on a page. Null in tests and when nothing is persisted.
  final Future<Uint8List?> Function(String assetId)? _loadAsset;

  RealChatService({
    required this.keys,
    Future<Uint8List?> Function(String assetId)? loadAsset,
    AnthropicClient? anthropicClient,
    GeminiClient? geminiClient,
    OpenAiCompatibleClient? openAiClient,
    OpenAiImageClient? openAiImageClient,
    FluxClient? fluxClient,
    ReplicateClient? replicateClient,
    FalClient? falClient,
    ElevenLabsClient? elevenLabsClient,
    HeygenClient? heygenClient,
    OpenAiVideoClient? openAiVideoClient,
    ProviderRegistry? registry,
    ModelRouter? router,
    MockChatService? mockFallback,
    Set<String> Function()? managedProviders,
    Future<ProviderAccess?> Function(String provider)? managedAccess,
  })  : _loadAsset = loadAsset,
        _managedProviders = managedProviders ?? _noManagedProviders,
        _managedAccess = managedAccess,
        _anthropic = anthropicClient ?? AnthropicClient(),
        _gemini = geminiClient ?? GeminiClient(),
        _openAi = openAiClient ?? OpenAiCompatibleClient(),
        _openAiImages = openAiImageClient ?? OpenAiImageClient(),
        _flux = fluxClient ?? FluxClient(),
        _replicate = replicateClient ?? ReplicateClient(),
        _fal = falClient ?? FalClient(),
        _elevenLabs = elevenLabsClient ?? ElevenLabsClient(),
        _heygen = heygenClient ?? HeygenClient(),
        _openAiVideo = openAiVideoClient ?? OpenAiVideoClient(),
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

  static Set<String> _noManagedProviders() => const {};

  /// Whether this turn can reach [providerId] at all — with the member's own
  /// key, or on their membership.
  ///
  /// Passed to [chooseProvider] everywhere `keys.hasKey` used to be, so "Auto"
  /// sees a covered provider exactly as it sees a keyed one.
  bool _canUse(String providerId) =>
      keys.hasKey(providerId) || _spendable().contains(providerId);

  /// The providers a membership can actually pay for, which is narrower than
  /// the providers a key is stored for.
  ///
  /// The vault will hold a HeyGen or ElevenLabs key quite happily; the proxy
  /// will not forward to either, because its allowlist is the chat endpoints.
  /// Filtering here rather than trusting the stored list is what stops routing
  /// choosing a provider whose credential cannot be attached.
  Set<String> _spendable() =>
      _managedProviders().intersection(proxyableProviders);

  /// The "can this turn reach that provider" test for a particular [route].
  ///
  /// Routing has to ask a per-provider question, but the honest answer depends
  /// on the route: a membership pays for text and not for pixels. So the route
  /// picks the predicate, at the call site that already knows it, which makes
  /// the eleven `chooseProvider` calls correct by construction rather than by
  /// being classified one at a time.
  ///
  /// Without this, a member with no key of their own asked for an image, Auto
  /// picked the provider their *membership* covered, and the image client sent
  /// an empty key — a 401 from OpenAI reported as a bad key, for a key they
  /// never had. Before memberships existed that turn fell back to the
  /// simulation, so it was a regression as well as a wrong sentence.
  bool Function(String) _usableFor(ChatRoute route) =>
      membershipCovers(route) ? _canUse : keys.hasKey;

  /// Who pays for this call.
  ///
  /// **Membership first**, then the member's own key. They pay monthly for the
  /// plan, so it should be the thing that gets spent — and because
  /// `AccountStore` only offers managed access while the subscription is
  /// active and under its ceiling, running out falls back to their own key
  /// rather than stopping them.
  ///
  /// Null means neither is available, and the caller falls back to the mock
  /// exactly as it did before any of this existed.
  Future<ProviderAccess?> _accessFor(String providerId) async {
    final managed = await _managedAccess?.call(providerId);
    if (managed != null) return managed;
    final key = keys.keyFor(providerId);
    return key.isEmpty ? null : DirectKey(key);
  }

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
          registry: _registry,
          hasKey: _usableFor(ChatRoute.imageGen),
          onWeb: kIsWeb);
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

      // "Put this image in the website." The picture exists already, so this
      // turn reuses those bytes rather than asking an image provider for a
      // second one — which would answer a different question and cost money.
      final existingImage =
          turn is StudioTurn ? turn.existingImage : null;
      if (existingImage != null &&
          turn is StudioTurn &&
          turn.composeTarget != null) {
        final bytes = await _resolveImageBytes(existingImage);
        if (bytes != null) {
          final target = turn.composeTarget!;
          controller.add(RoutingDetected(StudioType.codeStudio));
          controller.add(ArtifactUpdated(target.withNewVersion(
              existingImage.kind == GeneratedMediaKind.audio
                  ? applyGeneratedAudio(target.latest.content, bytes,
                      label: existingImage.alt)
                  : applyGeneratedImage(target.latest.content, bytes,
                      altText: existingImage.alt),
              DateTime.now())));
          controller.add(MessageDelta(
              'Added it to "${target.title}" as a new version.'));
          controller.add(const MessageComplete());
          await controller.close();
          return;
        }
      }

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
              // Putting an existing image on a page is a page build, whatever
              // the classifier makes of the sentence. It sees one message with
              // no conversation around it, and "put this image in the website"
              // reads to it like an image request — which is how the turn ended
              // up generating prose instead of a page.
              : wantsBoth || existingImage != null
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

      // A voiceover is a real deliverable when a voice provider is keyed: the
      // best text provider writes the script and ElevenLabs speaks it.
      //
      // This used to fall off the end of the client-kind switch below — which
      // knows about chat clients only — into the mock, so a user with a paid
      // ElevenLabs key got the built-in synthesizer's "Aria · Friendly" card
      // and no indication that their key had never been touched.
      if (_wantsSpokenAudio(route, userInput)) {
        final voiceId = chooseProvider(ChatRoute.voice,
          registry: _registry,
          hasKey: _usableFor(ChatRoute.voice),
          onWeb: kIsWeb);
        if (voiceId != null) {
          await _runVoice(controller, userInput);
          await controller.close();
          return;
        }
      }

      // Music: a real track when a music provider is keyed. Like video, this
      // route had no live executor — every song was the local synthesizer's
      // "Rising Pulse", whatever keys were present.
      if (route == ChatRoute.audio && !_wantsSpokenAudio(route, userInput)) {
        if (keys.hasKey('elevenlabs')) {
          await _runMusic(controller, userInput);
          await controller.close();
          return;
        }
      }

      // Video: a real render when a video provider is keyed. Before this the
      // route had no executor at all — it fell off the end of the client-kind
      // switch into the mock, so every video was the simulated card no matter
      // which keys were present.
      if (route == ChatRoute.video) {
        final videoId = chooseProvider(ChatRoute.video,
          registry: _registry,
          hasKey: _usableFor(ChatRoute.video),
          onWeb: kIsWeb);
        if (videoId != null) {
          await _runVideo(controller, userInput);
          await controller.close();
          return;
        }
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
          chooseProvider(route,
          registry: _registry,
          hasKey: _usableFor(route),
          onWeb: kIsWeb);
      final provider = providerId == null ? null : _registry.byId(providerId);

      final pageContributors =
          turn is StudioTurn ? turn.contributors : const <StudioType>{};
      final reviseTarget = turn is StudioTurn ? turn.reviseTarget : null;

      // An image turn is decided by the *route*, not by which client the
      // provider happens to use. Branching on clientKind first sent OpenAI's
      // image requests to chat-completions, because OpenAI shares its chat
      // wire shape with Groq and Mistral — so declaring the image capability
      // alone would have produced a text reply where a picture was asked for.
      if (providerId != null && route == ChatRoute.imageGen) {
        await _runImageWithClarification(controller, conversation, userInput,
            turn.effectiveInput, turn.isAnsweringClarification, providerId);
        await controller.close();
        return;
      }

      switch (provider?.clientKind) {
        case ProviderClientKind.anthropic:
          await _runAnthropicChat(controller, conversation, userInput,
              attachments, options, route, pageContributors, reviseTarget,
              existingImage);
        case ProviderClientKind.gemini:
          await _runGeminiChat(controller, conversation, userInput,
              attachments, options, route,
              pageContributors: pageContributors,
              reviseTarget: reviseTarget,
              existingImage: existingImage);
        case ProviderClientKind.openAiCompatible:
          await _runOpenAiChat(controller, conversation, userInput, attachments,
              options, provider!,
              model: _autoModelFor(provider, route),
              route: route,
              pageContributors: pageContributors,
              reviseTarget: reviseTarget,
              existingImage: existingImage);
        default:
          // No live provider — video and audio have none, and neither does a
          // user with no keys at all. Flux never reaches here either: it
          // serves only the image capability, so every Flux turn is taken by
          // the image branch above.
          await _delegateToMock(controller, conversation, userInput, null,
              attachments, options);
          return;
      }
      await controller.close();
    } catch (e) {
      // Not `e.toString()`: that printed the provider's whole JSON error
      // envelope into the chat. See `readableProviderError` — the provider's
      // own sentence is kept, because with bring-your-own-key *which* failure
      // it was is the entire diagnosis.
      controller.add(MessageError(readableProviderError(e)));
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
        chooseProvider(ChatRoute.webSearch,
          registry: _registry,
          hasKey: _usableFor(ChatRoute.webSearch),
          onWeb: kIsWeb);

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
        final anthropicAccess = await _accessFor('anthropic');
        final geminiAccess = await _accessFor('gemini');
        final events = searchId == 'anthropic'
            ? _anthropic.streamChat(
                access: anthropicAccess ?? DirectKey(keys.anthropicKey),
                conversation: _emptyConversation(),
                userInput: '$ask$query',
                model: AnthropicApiConfig.sonnetModel,
                tools: const [AnthropicTools.webSearch],
                maxContinuations: 3,
              )
            : _gemini.streamChat(
                access: geminiAccess ?? DirectKey(keys.geminiKey),
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
      final attempt = await _tryHeygenVideo(script);
      if (attempt.video != null) {
        controller.add(StudioResultReady(attempt.video!));
        controller.add(const MessageDelta(
            '\n\nRendered — open it in a new tab from the card '
            'above.'));
        controller.add(const MessageComplete());
        return;
      }
      // A Heygen key that cannot render used to fall through in silence, so
      // the user got the simulated card and no way to tell whether the key,
      // the avatar, or the account was the problem.
      if (attempt.problem != null) {
        controller.add(MessageDelta('${attempt.problem}\n\n'));
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
  Future<({VideoResult? video, String? problem})> _tryHeygenVideo(
      String script) async {
    // `_canUse`, not `keys.hasKey`: a membership pays for avatars now, and
    // gating on a stored key is what kept every media route on the simulation
    // for a member who had one.
    if (!_canUse('heygen')) return (video: null, problem: null);
    final access = await _accessFor('heygen');
    if (access == null) return (video: null, problem: null);
    try {
      final video = await _heygen.generateAvatarVideo(
        access: access,
        script: script,
      );
      return (
        video: VideoResult(
          prompt: script,
          durationSec: 10,
          aspectRatio: '16:9',
          identityLock: true,
          seed: StudioResponseBank.seedFromString(script),
          videoUrl: video.videoUrl,
          posterUrl: video.thumbnailUrl,
          providerLabel: 'Heygen',
        ),
        problem: null
      );
    } on SseHttpException catch (e) {
      return (video: null, problem: heygenProblem(e.statusCode, e.body));
    } catch (e) {
      return (video: null, problem: 'Heygen: $e');
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
      final attempt = await _tryHeygenVideo(script);
      if (attempt.video != null) {
        controller.add(StudioResultReady(attempt.video!));
        controller.add(const MessageDelta(
            '\n\nRendered — open it in a new tab from the card '
            'above.'));
        controller.add(const MessageComplete());
        return;
      }
      // No Heygen key (or the render failed): a portrait + synthesized voice.
      // Any keyed image provider draws the portrait, not Gemini alone.
      final portraitId =
          chooseProvider(ChatRoute.imageGen,
          registry: _registry,
          hasKey: _usableFor(ChatRoute.imageGen),
          onWeb: kIsWeb);
      final images = portraitId != null
          ? await _generatePhotos(
              portraitId, '$userInput, portrait headshot', 1)
          : await _generateProceduralPhotos(userInput, 1);
      if (images.isNotEmpty) {
        controller
            .add(ImageGenerated(pngBytes: images.first, alt: 'Avatar portrait'));
      }
    }

    controller.add(
        StudioResultReady(await _spokenOrSynthesized(kind, userInput, script)));
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
    final id = chooseProvider(ChatRoute.chat,
          registry: _registry,
          hasKey: _usableFor(ChatRoute.chat),
          onWeb: kIsWeb);
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
    final seed = BrandPackService.seedFor(name);

    Uint8List? logo;
    final imageId =
        chooseProvider(ChatRoute.imageGen,
          registry: _registry,
          hasKey: _usableFor(ChatRoute.imageGen),
          onWeb: kIsWeb);
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
          registry: _registry,
          hasKey: _usableFor(ChatRoute.imageGen),
          onWeb: kIsWeb);
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
    GeneratedImage? existingImage,
  }) async {
    controller.add(RoutingDetected(route.studioType));
    final events = _gemini.streamChat(
      access: await _accessFor('gemini') ?? DirectKey(keys.geminiKey),
      conversation: conversation,
      userInput: userInput,
      model: model ?? GeminiApiConfig.flashModel,
      attachments: attachments,
      systemPrompt: systemPromptForCodeTurn(options.systemPrompt,
          isCode: route == ChatRoute.code,
          hasGeneratedImage:
              existingImage?.kind == GeneratedMediaKind.image,
          hasGeneratedAudio:
              existingImage?.kind == GeneratedMediaKind.audio),
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
      existingImage: existingImage,
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
    GeneratedImage? existingImage,
  }) async {
    controller.add(RoutingDetected(route.studioType));
    final events = _openAi.streamChat(
      access: await _accessFor(provider.id) ?? DirectKey(keys.keyFor(provider.id)),
      baseUrl: provider.baseUrl!,
      model: model,
      displayName: _registry.displayNameForModel(model),
      conversation: conversation,
      userInput: userInput,
      attachments: attachments,
      systemPrompt: systemPromptForCodeTurn(options.systemPrompt,
          isCode: route == ChatRoute.code,
          hasGeneratedImage:
              existingImage?.kind == GeneratedMediaKind.image,
          hasGeneratedAudio:
              existingImage?.kind == GeneratedMediaKind.audio),
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
      existingImage: existingImage,
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

  /// The image stream for the chosen image provider. All three map onto the
  /// same ImageGenerated → ImageBlock path, which is why adding one is a case
  /// here and nothing else.
  Stream<ChatEvent> _imageStream(String providerId, String prompt) async* {
    // Flux, Replicate and fal are the member's own keys only: they are not in
    // the proxy's table at all, so there is no managed route to offer and
    // `_spendable()` never selects them for a membership.
    if (providerId == 'flux' || providerId == 'replicate' || providerId == 'fal') {
      yield* switch (providerId) {
        'flux' => _flux.generateImage(apiKey: keys.keyFor('flux'), prompt: prompt),
        'replicate' => _replicate.generateImage(
            apiKey: keys.keyFor('replicate'), prompt: prompt),
        _ => _fal.generateImage(apiKey: keys.keyFor('fal'), prompt: prompt),
      };
      return;
    }

    // OpenAI and Gemini go through the same access resolution as every text
    // call, which is what makes a membership cover pictures.
    final access = await _accessFor(providerId) ??
        DirectKey(providerId == 'gemini' ? keys.geminiKey : keys.keyFor(providerId));

    yield* providerId == 'openai'
        ? _openAiImages.generateImage(
            access: access,
            prompt: prompt,
            baseUrl: _registry.byId('openai')?.baseUrl ??
                'https://api.openai.com/v1',
          )
        : _gemini.generateImage(access: access, prompt: prompt);
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
        'Done — it\'s live in "${target.title}" as a new version.'));
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
    Artifact? reviseTarget, [
    GeneratedImage? existingImage,
  ]) async {
    controller.add(RoutingDetected(route.studioType));

    final model = options.modelPin ?? AnthropicApiConfig.defaultModel;

    // Server tools are offered on every turn and the model decides whether to
    // reach for them. They used to be composer toggles, which asked the user
    // to predict — before writing the message — whether the answer would need
    // fresh information or a calculation. Nobody knows that in advance, so the
    // toggles were mostly off and the tools mostly unused. Offering a tool
    // costs a little prompt overhead; invoking one is the model's call.
    final tools = <Map<String, dynamic>>[
      AnthropicTools.webSearch,
      AnthropicTools.codeExecution,
    ];

    final events = _anthropic.streamChat(
      access: await _accessFor('anthropic') ?? DirectKey(keys.anthropicKey),
      conversation: conversation,
      userInput: userInput,
      model: model,
      attachments: attachments,
      systemPrompt: systemPromptForCodeTurn(options.systemPrompt,
          isCode: route == ChatRoute.code,
          hasGeneratedImage:
              existingImage?.kind == GeneratedMediaKind.image,
          hasGeneratedAudio:
              existingImage?.kind == GeneratedMediaKind.audio),
      tools: tools,
      extendedThinking: options.extendedThinking,
      maxTokens: route == ChatRoute.code
          ? AnthropicApiConfig.codeMaxTokens
          : AnthropicApiConfig.defaultMaxTokens,
    );

    await _streamText(
      controller,
      events,
      conversation: conversation,
      userInput: userInput,
      route: route,
      pageContributors: pageContributors,
      reviseTarget: reviseTarget,
      existingImage: existingImage,
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
    GeneratedImage? existingImage,
  }) async {
    final buffer = StringBuffer();
    // Fenced code is held back rather than streamed into the transcript: when
    // it becomes an artifact, streaming it too showed the same page twice —
    // once as a wall of markup in the chat, once as the artifact. The prose
    // around it still streams. Anything held that does not become an artifact
    // is replayed below, so nothing is ever silently dropped.
    final fences = FenceFilter();
    var failed = false;
    var producedArtifact = false;
    var writing = false;

    await for (final event in events) {
      if (event is MessageDelta) {
        buffer.write(event.chunk);
        final prose = fences.feed(event.chunk);
        if (prose.isNotEmpty) controller.add(MessageDelta(prose));
        // The fence opening is the moment the deliverable starts being
        // written. The UI shows the build animation for exactly this window;
        // before it, the model is still writing the sentence that introduces
        // the thing, and claiming "Building" then claims work not yet begun.
        if (fences.writingCode != writing) {
          writing = fences.writingCode;
          controller.add(writing
              ? const ToolUseStarted(
                  id: writingToolId, tool: writingToolName, label: 'Building')
              : const ToolUseFinished(id: writingToolId));
        }
        continue; // the filtered delta above replaces this one
      }
      if (event is MessageError) failed = true;

      // Every way a reply can end, not just the clean one. Claude yields
      // MessageIncomplete when it stops at the output ceiling — which is
      // exactly what a long single-file website does — and handling only
      // MessageComplete meant the held page was flushed nowhere, extracted
      // nowhere, and replayed nowhere. The user saw the prose intro and then
      // blank space where the site should have been. Before fenced code was
      // withheld at all it streamed through raw, so this was a regression
      // that made a truncated page worse than useless: invisible.
      //
      // The invariant: withholding is a presentation choice, so every exit
      // path either turns held text into an artifact or puts it back in the
      // reply.
      final ending = event is MessageComplete ||
          event is MessageIncomplete ||
          event is MessageError;
      if (ending) {
        if (writing) {
          // A reply cut off mid-fence would otherwise leave the animation
          // running under a finished message forever.
          writing = false;
          controller.add(const ToolUseFinished(id: writingToolId));
        }
        final trailing = fences.flush();
        if (trailing.isNotEmpty) controller.add(MessageDelta(trailing));
        // Extraction only on a clean finish. A page cut off mid-tag is not a
        // deliverable — it would preview as a broken document and hide the
        // fact that it never finished.
        final cleanFinish = event is MessageComplete && !failed;
        // Code-routed replies whose fenced block is substantial become an
        // artifact, mirroring the mock's behavior.
        //
        // The second condition is a safety net rather than a nicety. Routing
        // is a classification and it will sometimes be wrong — most visibly
        // on a follow-up like "give it to me as an artifact", which the
        // router sees without any conversation around it. When it is wrong,
        // the old gate silently discarded a finished deliverable into a chat
        // bubble: unreadable, un-runnable, and impossible to download or
        // revise. A reply carrying an entire HTML document is never better
        // off inline, so route or no route, it becomes an artifact.
        if (cleanFinish &&
            (route == ChatRoute.code ||
                repliedWithWholeDocument(buffer.toString()))) {
          var artifact = extractCodeArtifact(
              buffer.toString(), conversation.id,
              request: userInput);
          if (artifact != null) {
            // The image the user pointed at goes in here, not in the model's
            // output — it never saw the picture. It was asked to leave a
            // placeholder; if it did, the bytes land exactly where it put
            // them, and if it did not they land at the top of the page.
            // Every artifact kind, not just HTML. "Put it in a jsx website"
            // produces a *code* artifact, and gating on html meant the model
            // was asked to leave a placeholder that nothing ever replaced —
            // shipping a component with a literal {{shift:image}} in its src.
            if (existingImage != null) {
              final bytes = await _resolveImageBytes(existingImage);
              if (bytes != null) {
                // Replaces the one version rather than adding a second: this
                // artifact has not reached the UI yet, so a "v1 / v2" here
                // would offer to step back to a page the user never saw.
                artifact = _withContent(
                    artifact,
                    existingImage.kind == GeneratedMediaKind.audio
                        ? applyGeneratedAudio(artifact.latest.content, bytes,
                            label: existingImage.alt)
                        : applyGeneratedImage(artifact.latest.content, bytes,
                            altText: existingImage.alt));
              }
            }
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
            producedArtifact = true;
          }
        }
        // A question the model asked with tappable answers. Parsed from the
        // whole reply rather than the held text, so it works whether or not
        // anything else was fenced.
        final choice = findChoiceIn(buffer.toString());
        if (choice != null) {
          controller.add(ChoiceOffered(
            id: _uuid.v4(),
            question: choice.question,
            options: choice.options,
            multiSelect: choice.multiSelect,
          ));
        }

        // Held code that no artifact was made of belongs back in the reply:
        // a snippet too short to be a deliverable, a turn where extraction
        // declined, or a reply that was cut off. Withholding is a
        // presentation choice, never a deletion.
        if (!producedArtifact && fences.sawFence) {
          // Minus the choice block, but only when it actually became buttons.
          // A block that failed to parse is just text the model wrote, and
          // dropping it would lose content to a malformation the user never
          // sees.
          final held = fences.replayText();
          final replay = choice == null ? held : stripChoiceBlock(held);
          if (replay.isNotEmpty) controller.add(MessageDelta(replay));
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
      // Whichever image provider Auto would pick — not Gemini specifically.
      // Hardcoding Gemini here meant an OpenAI or Flux user got procedural
      // placeholder art inside a page they had paid a real key to build.
      final imageId =
          chooseProvider(ChatRoute.imageGen,
          registry: _registry,
          hasKey: _usableFor(ChatRoute.imageGen),
          onWeb: kIsWeb);
      final images = imageId != null
          ? await _generatePhotos(imageId, userInput, count)
          : await _generateProceduralPhotos(userInput, count);
      if (images.isNotEmpty) {
        html = embedImageGallery(html, images, altText: userInput);
      }
    }

    return _withContent(artifact, html);
  }

  /// [artifact] with its content replaced — one version, not a new one. Used
  /// while an artifact is still being assembled and has never been displayed.
  static Artifact _withContent(Artifact artifact, String content) => Artifact(
        id: artifact.id,
        conversationId: artifact.conversationId,
        title: artifact.title,
        kind: artifact.kind,
        language: artifact.language,
        versions: [
          ArtifactVersion(content: content, createdAt: DateTime.now())
        ],
      );

  /// The bytes behind a [GeneratedImage], wherever they happen to live: still
  /// in memory from this session, in the asset store after a reload, or — in
  /// demo mode, which stores none — repainted from the same seed.
  ///
  /// Null when none of the three can supply them, which the callers treat as
  /// "carry on without the image" rather than failing the turn.
  Future<Uint8List?> _resolveImageBytes(GeneratedImage image) async {
    if (image.pngBytes != null) return image.pngBytes;
    final assetId = image.assetId;
    final load = _loadAsset;
    if (assetId != null && load != null) {
      final bytes = await load(assetId);
      if (bytes != null) return bytes;
    }
    final seed = image.seed;
    if (seed != null && image.kind == GeneratedMediaKind.image) {
      return rasterizeGradientArt(seed: seed);
    }
    return null;
  }

  /// A real composed track, or the synthesized card with the reason.
  Future<void> _runMusic(
    StreamController<ChatEvent> controller,
    String userInput,
  ) async {
    controller.add(const RoutingDetected(StudioType.musicStudio));

    final seed = StudioResponseBank.seedFromString(userInput);
    Uint8List? bytes;
    String? problem;
    try {
      bytes = await _elevenLabs.compose(
          access: await _accessFor('elevenlabs') ??
              DirectKey(keys.keyFor('elevenlabs')),
          prompt: userInput);
    } on SseHttpException catch (e) {
      problem = elevenLabsProblem(e.statusCode, e.body);
    } catch (e) {
      problem = 'Couldn\'t reach ElevenLabs for the track, so this is the '
          'built-in synthesizer. ($e)';
    }

    if (problem != null) controller.add(MessageDelta('$problem\n\n'));
    controller.add(StudioResultReady(AudioResult(
      kind: AudioKind.music,
      title: bytes == null ? 'Rising Pulse' : 'Track',
      subtitle: bytes == null ? 'Synthesized' : 'Composed',
      durationSec: 30,
      seed: seed,
      transcript: userInput,
      audioBytes: bytes ??
          AudioSynthService.synthesizeWav(
              seed: seed, durationSec: 20, bpm: 100, speechLike: false),
    )));
    controller.add(const MessageDelta(
        '\n\nPlay or download it from the card above.'));
    controller.add(const MessageComplete());
  }

  /// A real rendered video, or the simulated card with the reason when the
  /// render could not happen.
  Future<void> _runVideo(
    StreamController<ChatEvent> controller,
    String userInput,
  ) async {
    controller.add(const RoutingDetected(StudioType.videoStudio));

    final seed = StudioResponseBank.seedFromString(userInput);
    final simulated = VideoResult(
      prompt: userInput,
      durationSec: 4,
      aspectRatio: '16:9',
      identityLock: false,
      seed: seed,
    );

    String? problem;
    Uint8List? bytes;
    try {
      bytes = await _openAiVideo.render(
          access: await _accessFor('openai') ?? DirectKey(keys.keyFor('openai')),
          prompt: userInput);
    } on SseHttpException catch (e) {
      problem = openAiVideoProblem(e.statusCode, e.body);
    } catch (e) {
      problem = 'Couldn\'t reach OpenAI for the video, so this is a '
          'simulated clip. ($e)';
    }

    if (problem != null) controller.add(MessageDelta('$problem\n\n'));
    controller.add(StudioResultReady(bytes == null
        ? simulated
        : VideoResult(
            prompt: userInput,
            durationSec: 4,
            aspectRatio: '16:9',
            identityLock: false,
            seed: seed,
            providerLabel: 'Sora',
            videoBytes: bytes,
          )));
    controller.add(const MessageComplete());
  }

  /// A real spoken voiceover: the best text provider writes the script, the
  /// voice provider speaks it, and the card carries the actual audio.
  ///
  /// The script is written rather than read straight from the prompt because
  /// "a voiceover talking about pink flowers" is a brief, not a line to read —
  /// speaking it back verbatim would be the wrong deliverable.
  Future<void> _runVoice(
    StreamController<ChatEvent> controller,
    String userInput,
  ) async {
    controller.add(const RoutingDetected(StudioType.voiceStudio));

    var script = '';
    try {
      script = (await _writeText(voiceScriptPrompt(userInput))).trim();
    } catch (_) {
      // Fall through to the template below.
    }
    if (script.isEmpty) script = mockVoiceScript(userInput);

    final base = AudioResult(
      kind: AudioKind.voice,
      title: 'Voiceover',
      subtitle: 'Voiceover',
      durationSec: max(4, (script.split(RegExp(r'\s+')).length / 2.5).round()),
      seed: StudioResponseBank.seedFromString(userInput),
      transcript: script,
    );

    final spoken = await _speakOrKeep(base, script);
    if (spoken.problem != null) {
      // Silence here is what made this feel broken: the user got a synthesized
      // card and no way to tell whether the key, the account or the network
      // was at fault.
      controller.add(MessageDelta('${spoken.problem}\n\n'));
    }
    controller.add(StudioResultReady(spoken.audio));
    controller.add(const MessageDelta(
        '\n\nPlay or download it from the card above — say the word for a '
        'different tone, pace or voice.'));
    controller.add(const MessageComplete());
  }

  /// [base] upgraded to real speech when a voice provider is keyed, or kept as
  /// the synthesized card with a reason when it is not or the call fails.
  Future<({AudioResult audio, String? problem})> _speakOrKeep(
    AudioResult base,
    String script,
  ) async {
    final voiceId = chooseProvider(ChatRoute.voice,
          registry: _registry,
          hasKey: _usableFor(ChatRoute.voice),
          onWeb: kIsWeb);
    if (voiceId != 'elevenlabs') return (audio: base, problem: null);
    try {
      final pcm = await _elevenLabs.speak(
          access: await _accessFor('elevenlabs') ??
              DirectKey(keys.keyFor('elevenlabs')),
          text: script);
      if (pcm.isEmpty) {
        return (audio: base, problem: 'ElevenLabs returned no audio, so this '
            'is the built-in synthesizer.');
      }
      return (
        audio: AudioResult(
          kind: base.kind,
          title: base.title,
          subtitle: base.subtitle,
          durationSec: base.durationSec,
          seed: base.seed,
          transcript: base.transcript,
          audioBytes: AudioSynthService.wavFromPcm16(pcm,
              sampleRate: ElevenLabsClient.sampleRate),
        ),
        problem: null
      );
    } on SseHttpException catch (e) {
      return (audio: base, problem: elevenLabsProblem(e.statusCode, e.body));
    } catch (e) {
      return (
        audio: base,
        problem: 'Couldn\'t reach ElevenLabs, so this is the built-in '
            'synthesizer. ($e)'
      );
    }
  }

  /// The audio card for a media pair, spoken by a real voice provider when one
  /// is keyed and synthesized locally otherwise.
  ///
  /// A failure here falls back rather than surfacing: the turn already has a
  /// script and a card to put it in, and a silent card is a worse outcome than
  /// a synthesized one. Music is left alone — ElevenLabs speaks, it does not
  /// score.
  Future<AudioResult> _spokenOrSynthesized(
    CompositionKind kind,
    String userInput,
    String script,
  ) async {
    final result = mediaPairAudio(kind, userInput, script);
    if (result.kind != AudioKind.voice) return result;
    return (await _speakOrKeep(result, script)).audio;
  }

  Future<List<Uint8List>> _generatePhotos(
      String providerId, String prompt, int count) async {
    final images = <Uint8List>[];
    for (var i = 0; i < count; i++) {
      await for (final event in _imageStream(providerId, prompt)) {
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
  /// Whether [text] contains a fenced block holding a *whole* HTML document.
  ///
  /// Deliberately narrow: a complete page (doctype, or `<html>` paired with
  /// `</html>`) is a deliverable, whereas a handful of tags quoted to explain
  /// something belongs in the conversation. Matching any HTML at all would
  /// turn every answer that mentions a `<div>` into an artifact.
  static bool repliedWithWholeDocument(String text) {
    for (final match in _fencedBlock.allMatches(text)) {
      final code = match.group(2)!.trim();
      final lower = code.toLowerCase();
      if (lower.startsWith('<!doctype html') ||
          (lower.contains('<html') && lower.contains('</html>'))) {
        return true;
      }
    }
    return false;
  }

  static final _fencedBlock =
      RegExp(r'```([A-Za-z0-9+#_-]*)\n([\s\S]*?)```');

  static Artifact? extractCodeArtifact(
    String text,
    String conversationId, {
    String? title,
    String request = '',
  }) {
    final match = _fencedBlock.firstMatch(text);
    if (match == null) return null;
    final code = match.group(2)!.trim();
    if (code.split('\n').length < 5) return null;
    final language = match.group(1)!.toLowerCase();
    final isHtml = language == 'html' || code.startsWith('<!DOCTYPE');
    return Artifact(
      id: _uuid.v4(),
      conversationId: conversationId,
      // Named from what was built, not from the sentence that asked for it —
      // the page's own <title>/<h1>, or the component it declares. The request
      // is the fallback, and 'Generated page' the fallback's fallback.
      title: title ??
          titleFromArtifact(code,
              language: isHtml ? null : language, request: request),
      kind: isHtml ? ArtifactKind.html : ArtifactKind.code,
      language: language.isEmpty ? null : language,
      versions: [ArtifactVersion(content: code, createdAt: DateTime.now())],
    );
  }
}

/// The single seam the UI talks to: picks the live service when there is any
/// way to pay for a turn, the mock otherwise — per message, so adding a key or
/// being granted a plan takes effect immediately with zero UI branching.
///
/// **Two ways to pay, and for a while this only knew about one.** It asked
/// `keys.isLive` — "has this device stored a provider key" — so a member with
/// an active membership and no key of their own never reached the live service
/// at all. Everything below it worked: the proxy was deployed, the plan was
/// active, the vault held a key, and the Setup card's own test call went
/// through and came back. Every actual turn still got the simulation, because
/// the decision about whether to *try* was made one layer above all of it.
///
/// That is the whole bug in one sentence: the thing a membership buys is the
/// right to send a turn without a key, and the gate in front of every turn
/// asked for a key.
class ChatServiceSelector implements ChatService {
  final ApiKeysStore keys;
  final ChatService real;
  final ChatService mock;

  /// The providers a membership currently pays for. A function rather than a
  /// value because a plan can be granted, spent, or lapse while the app is
  /// open, and this is read per message.
  final Set<String> Function() managedProviders;

  ChatServiceSelector({
    required this.keys,
    required this.real,
    required this.mock,
    Set<String> Function()? managedProviders,
  }) : managedProviders = managedProviders ?? _none;

  static Set<String> _none() => const {};

  /// Whether this turn has any way of being paid for.
  bool get canGoLive => keys.isLive || managedProviders().isNotEmpty;

  @override
  Stream<ChatEvent> sendMessage({
    required Conversation conversation,
    required String userInput,
    StudioRequest? structuredRequest,
    List<Attachment> attachments = const [],
    ChatOptions options = ChatOptions.none,
  }) {
    final service = canGoLive ? real : mock;
    return service.sendMessage(
      conversation: conversation,
      userInput: userInput,
      structuredRequest: structuredRequest,
      attachments: attachments,
      options: options,
    );
  }
}
