import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/artifact.dart';
import '../models/attachment.dart';
import '../models/citation.dart';
import '../models/conversation.dart';
import '../models/studio_request.dart';
import '../models/studio_type.dart';
import '../state/api_keys_store.dart';
import 'artifact_composition.dart';
import 'chat_service.dart';
import 'deep_research_engine.dart';
import 'mock_chat_service.dart';
import 'procedural_art.dart';
import 'studio_composition.dart';
import 'providers/anthropic_api_config.dart';
import 'providers/anthropic_client.dart';
import 'providers/anthropic_tools.dart';
import 'providers/gemini_api_config.dart';
import 'providers/gemini_client.dart';
import 'router/model_router.dart';
import 'studio_clarification.dart';
import 'studio_response_bank.dart';

const _uuid = Uuid();

/// Which backend serves a routed request.
enum Executor { anthropic, gemini, mock }

/// The degradation matrix: each route runs on the best available provider,
/// falling back to the mock so every request still produces something.
/// Pure — unit-tested across all key combinations.
Executor chooseExecutor(
  ChatRoute route, {
  required bool hasAnthropic,
  required bool hasGemini,
}) {
  return switch (route) {
    // Image generation is a Gemini capability.
    ChatRoute.imageGen => hasGemini ? Executor.gemini : Executor.mock,
    // No live provider generates video/audio yet.
    ChatRoute.video || ChatRoute.audio => Executor.mock,
    // Text-shaped work prefers Claude, then Gemini, then the mock.
    _ => hasAnthropic
        ? Executor.anthropic
        : hasGemini
            ? Executor.gemini
            : Executor.mock,
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
  final ModelRouter _router;
  final MockChatService _mockFallback;

  RealChatService({
    required this.keys,
    AnthropicClient? anthropicClient,
    GeminiClient? geminiClient,
    ModelRouter? router,
    MockChatService? mockFallback,
  })  : _anthropic = anthropicClient ?? AnthropicClient(),
        _gemini = geminiClient ?? GeminiClient(),
        _router = router ??
            ModelRouter(
              client: anthropicClient,
              geminiClient: geminiClient,
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
        if (structuredRequest is ImageRequest && keys.hasGeminiKey) {
          await _runGeminiImage(controller, structuredRequest.prompt);
          return;
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

      final route = options.modelPin != null
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

      final executor = chooseExecutor(
        route,
        hasAnthropic: keys.hasAnthropicKey,
        hasGemini: keys.hasGeminiKey,
      );

      switch (executor) {
        case Executor.anthropic:
          await _runAnthropicChat(controller, conversation, userInput,
              attachments, options, route, wantsBoth);
        case Executor.gemini:
          if (route == ChatRoute.imageGen) {
            await _runGeminiImageWithClarification(
                controller, conversation, userInput, pending);
          } else {
            await _runGeminiChat(controller, conversation, userInput,
                attachments, options, route);
          }
        case Executor.mock:
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
    final useAnthropic = keys.hasAnthropicKey;

    Future<String> completeText(String prompt,
        {bool strongModel = false}) async {
      if (useAnthropic) {
        return _anthropic.complete(
          apiKey: keys.anthropicKey,
          model: strongModel
              ? AnthropicApiConfig.defaultModel
              : AnthropicApiConfig.haikuModel,
          prompt: prompt,
          maxTokens: strongModel ? 8000 : 300,
        );
      }
      return _gemini.complete(
        apiKey: keys.geminiKey,
        prompt: prompt,
        model: strongModel
            ? GeminiApiConfig.proModel
            : GeminiApiConfig.flashModel,
      );
    }

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
        final buffer = StringBuffer();
        final citations = <Citation>[];
        final events = useAnthropic
            ? _anthropic.streamChat(
                apiKey: keys.anthropicKey,
                conversation: _emptyConversation(),
                userInput: 'Search the web and concisely summarize the '
                    'key findings for: $query',
                model: AnthropicApiConfig.sonnetModel,
                tools: const [AnthropicTools.webSearch],
                maxContinuations: 3,
              )
            : _gemini.streamChat(
                apiKey: keys.geminiKey,
                conversation: _emptyConversation(),
                userInput: 'Search the web and concisely summarize the '
                    'key findings for: $query',
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

  Future<void> _runGeminiChat(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    List<Attachment> attachments,
    ChatOptions options,
    ChatRoute route,
  ) async {
    controller.add(RoutingDetected(route.studioType));
    final events = _gemini.streamChat(
      apiKey: keys.geminiKey,
      conversation: conversation,
      userInput: userInput,
      attachments: attachments,
      systemPrompt: options.systemPrompt,
      grounding: options.webSearch || route == ChatRoute.webSearch,
    );
    await controller.addStream(events);
  }

  /// Freeform image prompts get the same "ask before guessing" gate as the
  /// mock — Gemini's image endpoint is one-shot (no conversation), so this
  /// is the only chance to ask before spending a real generation call.
  Future<void> _runGeminiImageWithClarification(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    (StudioType, String)? pending,
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

    // "Add a hero image to the website": Gemini generates the asset, then
    // it's spliced into the artifact Claude (or a prior turn) already
    // built — two studios composing within one turn.
    final composeTarget =
        findArtifactCompositionTarget(conversation, effectiveInput);
    if (composeTarget != null) {
      await _composeGeminiImageIntoArtifact(
          controller, composeTarget, effectiveInput);
      return;
    }

    await _runGeminiImage(controller, effectiveInput, close: false);
  }

  /// Generates the image with the real Gemini endpoint, then splices the
  /// bytes into [target]'s HTML as a new artifact version instead of
  /// showing them as a separate inline image.
  Future<void> _composeGeminiImageIntoArtifact(
    StreamController<ChatEvent> controller,
    Artifact target,
    String prompt,
  ) async {
    controller.add(MessageDelta(
        'Generating the image with Gemini, then adding it into '
        '"${target.title}"…\n\n'));
    Uint8List? bytes;
    await for (final event
        in _gemini.generateImage(apiKey: keys.geminiKey, prompt: prompt)) {
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

  Future<void> _runGeminiImage(
    StreamController<ChatEvent> controller,
    String prompt, {
    bool close = true,
  }) async {
    if (close) {
      controller.add(RoutingDetected(ChatRoute.imageGen.studioType));
    }
    controller.add(const MessageDelta(
        'Routing this to Image Studio — generating with Gemini…\n\n'));
    await controller.addStream(
      _gemini.generateImage(apiKey: keys.geminiKey, prompt: prompt),
    );
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
    bool wantsCodeAndImage,
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
            if (wantsCodeAndImage && artifact.kind == ArtifactKind.html) {
              // Claude built the page; now Image Studio supplies the
              // photos for it, woven in before the artifact ever reaches
              // the UI — both studios contributing to the one turn.
              artifact = await _embedPhotosIntoArtifact(artifact, userInput);
            }
            controller.add(ArtifactCreated(artifact));
          }
        }
      }
      controller.add(event);
    }
  }

  /// Fills a freshly built HTML artifact with generated photos: real
  /// Gemini images when a Google key exists, otherwise the same
  /// procedurally rasterized art the mock uses, so the page is never left
  /// without visuals just because only an Anthropic key was configured.
  Future<Artifact> _embedPhotosIntoArtifact(
    Artifact artifact,
    String userInput,
  ) async {
    final count = photoCountHint(userInput);
    final images = keys.hasGeminiKey
        ? await _generateGeminiPhotos(userInput, count)
        : await _generateProceduralPhotos(userInput, count);
    if (images.isEmpty) return artifact;
    final html =
        embedImageGallery(artifact.latest.content, images, altText: userInput);
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
