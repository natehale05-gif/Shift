import '../conversation_media.dart';
import '../studio_detection.dart';
import 'mock_revision.dart';
import '../request_title.dart';
import '../../features/artifacts/interactive/interactive_render.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../../data/models/artifact.dart';
import '../../data/models/attachment.dart';
import '../../data/models/conversation.dart';
import '../../data/models/studio_request.dart';
import '../../data/models/studio_result.dart';
import '../../data/models/studio_type.dart';
import '../../data/models/usage_report.dart';
import '../../features/artifacts/artifact_composition.dart';
import '../../features/studios/media/audio_synth_service.dart';
import '../chat_service.dart';
import '../plan_turn.dart';
import '../turn_input.dart';
import '../turn_plan.dart';
import '../../features/artifacts/interactive/interactive_content.dart';
import '../../features/studios/media/procedural_art.dart';
import '../studio_composition.dart';
import '../../features/studios/studio_response_bank.dart';

const _uuid = Uuid();

/// Simulates the "middleware AI" that routes to specialized studio models.
/// Everything here is fabricated locally with artificial delay to mimic a
/// real streaming backend — no network calls. It deliberately exercises the
/// full [ChatEvent] vocabulary (thinking, tool use, citations, artifacts,
/// deep research) so every UI path works before any API key exists.
class MockChatService implements ChatService {
  final Random _random = Random();

  /// Reads a stored asset's bytes, so an image generated in an earlier session
  /// can still be put on a page. Null in tests and when nothing is persisted.
  final Future<Uint8List?> Function(String assetId)? _loadAsset;

  MockChatService({Future<Uint8List?> Function(String assetId)? loadAsset})
      : _loadAsset = loadAsset;

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
      // The decision half of the turn — which studio, what shape of answer —
      // is made once, by a pure function shared with the live service. This
      // method is now only the *execution* half: turning that plan into a
      // simulated event stream.
      final turn = planTurn(TurnInput(
        conversation: conversation,
        userInput: userInput,
        structuredRequest: structuredRequest,
        attachments: attachments,
        options: options,
      ));
      final studio = turn.studio;
      final effectiveInput = turn.effectiveInput;

      var thinking = StudioResponseBank.thinkingText(studio, effectiveInput);
      final system = options.systemPrompt ?? '';
      if (system.contains('Active project:')) {
        thinking += ' Applying the project\'s instructions and knowledge.';
      } else if (system.contains('standing instructions') ||
          system.contains('Address the user as')) {
        thinking += ' Applying your personalization settings.';
      }
      await _streamThinking(controller, thinking);

      await _delay(250, 600);
      controller.add(RoutingDetected(studio));

      if (attachments.isNotEmpty) {
        final names = attachments.map((a) => a.name).join(', ');
        await _streamText(
          controller,
          'Looking at your attached ${attachments.length == 1 ? 'file' : 'files'} '
          '($names) — simulated for now; a real model will read '
          '${attachments.length == 1 ? 'it' : 'them'} once an API key is added.\n\n',
        );
      }

      // Dispatch on the plan. The branch *order* that used to live here is now
      // part of planTurn; this switch only says how each kind is performed.
      switch (turn) {
        case InteractiveTurn(:final kind):
          await _runInteractive(controller, conversation, kind, userInput);
        case DiagramTurn():
          await _runDiagram(controller, userInput);
        case DeepResearchTurn():
          await _runDeepResearch(controller, conversation, userInput);
        case WebSearchTurn():
          await _runWebSearch(controller, userInput);
        case CopyFedTurn(:final kind):
          await _runCopyFedMedia(controller, kind, effectiveInput);
        case MediaPairTurn(:final kind):
          await _runMediaPair(controller, kind, effectiveInput);
        case StudioTurn(
            :final structuredRequest,
            :final composeTarget,
            :final composeKind,
            :final contributors,
            :final reviseTarget,
            :final existingImage,
            :final isAnsweringClarification,
          ):
          await _runStudioFlow(
            controller,
            conversation,
            studio,
            effectiveInput,
            structuredRequest,
            isAnsweringClarification,
            composeTarget,
            composeKind,
            contributors,
            reviseTarget,
            existingImage,
          );
      }

      controller.add(UsageReported(UsageReport(
        inputTokens: 40 + userInput.length ~/ 4,
        outputTokens: 120 + _random.nextInt(240),
        model: 'shift-mock-1',
      )));
      controller.add(const MessageComplete());
    } catch (e) {
      controller.add(MessageError(e.toString()));
    } finally {
      await controller.close();
    }
  }

  Future<void> _runStudioFlow(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    StudioType studio,
    String userInput,
    StudioRequest? structuredRequest,
    bool isAnsweringClarification,
    Artifact? composeTarget,
    ArtifactMediaKind? composeKind,
    Set<StudioType> pageContributors,
    Artifact? reviseTarget,
    GeneratedImage? existingImage,
  ) async {
    // Whether this turn is going to ask rather than generate. Decided up
    // front because it changes how the reply opens: "Here's the image you
    // asked for:" followed by a question is a promise the turn does not keep.
    final asking = studio != StudioType.middleware &&
        structuredRequest == null &&
        !isAnsweringClarification &&
        composeTarget == null &&
        pageContributors.isEmpty
        ? StudioResponseBank.clarifyingQuestion(studio, userInput)
        : null;

    final contributorNames =
        pageContributors.map((s) => s.displayName).toList();
    if (asking != null) {
      await _streamText(controller, asking);
      // The half of the question with a known answer set is offered as
      // options rather than asked in prose — a tap instead of a keyboard.
      final choice = StudioResponseBank.clarifyingChoice(studio);
      if (choice != null) {
        controller.add(ChoiceOffered(
          id: _uuid.v4(),
          question: choice.question,
          options: choice.options,
          multiSelect: choice.multiSelect,
        ));
      }
      return;
    }

    if (pageContributors.isNotEmpty) {
      await _streamText(controller,
          StudioResponseBank.pageAssemblyIntro(userInput, contributorNames));
    } else if (composeTarget != null) {
      await _streamText(
          controller,
          StudioResponseBank.compositionIntro(composeTarget.title,
              composeKind ?? ArtifactMediaKind.image));
    } else if (studio != StudioType.middleware && isAnsweringClarification) {
      await _streamText(controller, StudioResponseBank.clarificationAck(studio));
    } else {
      final introText = structuredRequest != null
          ? StudioResponseBank.routingIntro(studio, structuredRequest.summary)
          : StudioResponseBank.routingIntro(studio, userInput);
      await _streamText(controller, introText);
    }

    if (studio == StudioType.middleware) return;

    await _delay(500, 1100);
    final result = structuredRequest != null
        ? StudioResponseBank.buildResult(structuredRequest)
        : StudioResponseBank.buildResultFromFreeform(studio, userInput);

    // Set when this turn revised an existing artifact: a short phrase naming
    // the edit that was applied, or null when demo mode recognised none.
    String? revisionSummary;

    if (composeTarget != null) {
      // Two studios in one turn: a studio's output gets woven into the
      // artifact another studio already built, instead of standing alone.
      switch (composeKind ?? ArtifactMediaKind.image) {
        case ArtifactMediaKind.image:
          // "Put *this* image on the page" names one that already exists, so
          // reuse it. Generating a fresh one would put a different picture on
          // the page than the one the user was pointing at.
          await _composeImageIntoArtifact(controller, composeTarget,
              existingImage ?? _asGeneratedImage(result as ImageResult));
        case ArtifactMediaKind.audio:
          await _composeAudioIntoArtifact(controller, composeTarget, userInput);
        case ArtifactMediaKind.video:
          await _composeVideoIntoArtifact(controller, composeTarget, userInput);
      }
    } else if (studio == StudioType.codeStudio) {
      // Code output ships as an artifact (side panel), not an inline card —
      // the artifact IS the deliverable, with copy/download/versions there.
      revisionSummary = await _emitCodeArtifact(
          controller, conversation, userInput, result,
          pageContributors: pageContributors,
          reviseTarget: reviseTarget,
          existingImage: existingImage);
    } else {
      controller.add(StudioResultReady(result));
    }

    final followUp = pageContributors.isNotEmpty
        ? StudioResponseBank.pageAssemblyFollowUp(contributorNames)
        : composeTarget != null
            ? StudioResponseBank.compositionFollowUp(composeTarget.title,
                composeKind ?? ArtifactMediaKind.image)
            : reviseTarget != null
                ? (revisionSummary != null
                    ? StudioResponseBank.revisionFollowUp(revisionSummary)
                    : StudioResponseBank.revisionNotSimulated)
                : StudioResponseBank.studioFollowUp(studio);
    if (followUp.isNotEmpty) {
      await _streamText(controller, '\n\n$followUp');
    }
  }

  /// Copy & Scripts writes something, then a downstream studio produces from
  /// it in the same turn: a narrated voiceover, a scripted video, or a scored
  /// jingle. The written script is streamed as text and also carried on the
  /// media result (its transcript/prompt), so the handoff is visible.
  Future<void> _runCopyFedMedia(
    StreamController<ChatEvent> controller,
    CompositionKind kind,
    String userInput,
  ) async {
    await _streamText(controller, copyFedIntro(kind));
    await _delay(500, 1000);
    final script = mockScript(kind, userInput);
    await _streamText(controller, '\n\n$script');
    controller.add(StudioResultReady(copyFedResult(kind, userInput, script)));
    final followUp = copyFedFollowUp(kind);
    if (followUp.isNotEmpty) {
      await _streamText(controller, '\n\n$followUp');
    }
  }

  /// Media pairs: talkingAvatar shows a generated portrait (an inline image
  /// block) together with a voiceover card; scoredNarration shows a single
  /// narration-over-a-music-bed card. Both lead with Voice & Avatar.
  Future<void> _runMediaPair(
    StreamController<ChatEvent> controller,
    CompositionKind kind,
    String userInput,
  ) async {
    await _streamText(controller, mediaPairIntro(kind));
    await _delay(500, 1000);

    if (kind == CompositionKind.talkingAvatar) {
      final portrait = await rasterizeGradientArt(
          seed: StudioResponseBank.seedFromString(userInput));
      controller.add(ImageGenerated(pngBytes: portrait, alt: 'Avatar portrait'));
    }

    final script = mockScript(kind, userInput);
    controller.add(StudioResultReady(mediaPairAudio(kind, userInput, script)));

    final followUp = mediaPairFollowUp(kind);
    if (followUp.isNotEmpty) {
      await _streamText(controller, '\n\n$followUp');
    }
  }

  /// Builds an interactive artifact (recipe card / quiz / flashcards /
  /// checklist) with templated content — a self-contained interactive widget
  /// that runs live in the artifact panel, no API key required.
  /// Demo diagrams: streams a templated ```mermaid fence (rendered live by the
  /// markdown view). A real model writes its own mermaid in live mode.
  Future<void> _runDiagram(
    StreamController<ChatEvent> controller,
    String userInput,
  ) async {
    await _streamText(
        controller, 'Here\'s a diagram — it renders live right below.\n\n');
    await _delay(300, 700);
    await _streamText(controller, '```mermaid\n${_diagramFor(userInput)}\n```\n');
    await _streamText(controller,
        '\nAdd an API key in Settings and I\'ll draw a diagram tailored to '
        'your exact topic.');
  }

  static String _diagramFor(String input) {
    final s = input.toLowerCase();
    if (s.contains('sequence')) {
      return 'sequenceDiagram\n'
          '  participant U as User\n'
          '  participant A as SHIFT AI\n'
          '  participant S as Studio\n'
          '  U->>A: Send a request\n'
          '  A->>S: Route to the right studio\n'
          '  S-->>A: Return the result\n'
          '  A-->>U: Reply with the answer';
    }
    if (s.contains('mind')) {
      return 'mindmap\n'
          '  root((SHIFT AI))\n'
          '    Chat\n'
          '    Studios\n'
          '      Image\n'
          '      Video\n'
          '      Code\n'
          '    Memory';
    }
    if (s.contains('gantt')) {
      return 'gantt\n'
          '  title Project plan\n'
          '  dateFormat  YYYY-MM-DD\n'
          '  section Build\n'
          '  Design      :a1, 2026-01-01, 7d\n'
          '  Develop     :after a1, 14d\n'
          '  section Launch\n'
          '  Test        :2026-01-22, 5d\n'
          '  Ship        :2026-01-27, 2d';
    }
    return 'flowchart TD\n'
        '  A[Your request] --> B{Middleware AI}\n'
        '  B -->|creative| C[Studio]\n'
        '  B -->|question| D[Direct answer]\n'
        '  C --> E[Result]\n'
        '  D --> E';
  }

  Future<void> _runInteractive(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    InteractiveKind kind,
    String userInput,
  ) async {
    final topic = InteractiveArtifacts.parseTopic(userInput, kind);
    await _streamText(controller,
        'Here\'s an interactive ${kind.label} for "$topic" — it\'s live right '
        'here in the chat.');
    await _delay(500, 1000);

    // Cross-studio in demo mode: a recipe gets a procedural hero photo when
    // the prompt asks for one (Image Studio feeding Code Studio's widget).
    String? heroUri;
    if (kind == InteractiveKind.recipe) {
      final lower = userInput.toLowerCase();
      if (lower.contains('photo') ||
          lower.contains('image') ||
          lower.contains('picture')) {
        final bytes = await rasterizeGradientArt(
            seed: StudioResponseBank.seedFromString(topic));
        heroUri = 'data:image/png;base64,${base64Encode(bytes)}';
      }
    }

    final html = switch (kind) {
      InteractiveKind.recipe => InteractiveRender.renderRecipe(
          InteractiveArtifacts.templatedRecipe(topic),
          heroImageDataUri: heroUri),
      InteractiveKind.quiz => InteractiveRender.renderQuiz(
          InteractiveArtifacts.templatedQuiz(topic), '${_titleCase(topic)} Quiz'),
      InteractiveKind.flashcards => InteractiveRender.renderFlashcards(
          InteractiveArtifacts.templatedFlashcards(topic), '${_titleCase(topic)} Flashcards'),
      InteractiveKind.checklist => InteractiveRender.renderChecklist(
          InteractiveArtifacts.templatedChecklist(topic), _titleCase(topic)),
    };
    final title = switch (kind) {
      InteractiveKind.recipe => _titleCase(topic),
      InteractiveKind.quiz => '${_titleCase(topic)} Quiz',
      InteractiveKind.flashcards => '${_titleCase(topic)} Flashcards',
      InteractiveKind.checklist => _titleCase(topic),
    };
    controller.add(ArtifactCreated(InteractiveRender.build(
      kind: kind,
      conversationId: conversation.id,
      title: title,
      html: html,
    )));
    await _streamText(controller,
        '\n\nCheck off ingredients, flip cards, or score the quiz right in the '
        'card. Add an API key in Settings and I\'ll fill it with real content '
        'for your topic.');
  }

  static String _titleCase(String s) => s.isEmpty
      ? s
      : s
          .split(' ')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join(' ');

  /// Builds the base HTML page, then weaves in each contributor studio's
  /// output procedurally — photos, real copy, an audio player, a video
  /// block — so the whole page arrives assembled in one artifact version.
  Future<String> _assembleMockPage(
    String prompt,
    Set<StudioType> contributors,
  ) async {
    final seed = StudioResponseBank.seedFromString(prompt);
    final base = StudioResponseBank.htmlArtifactContent(titleFromRequest(prompt));

    var images = const <Uint8List>[];
    if (contributors.contains(StudioType.imageStudio)) {
      final count = photoCountHint(prompt);
      images = await Future.wait([
        for (var i = 0; i < count; i++) rasterizeGradientArt(seed: seed + i),
      ]);
    }

    final copy = contributors.contains(StudioType.copyScriptsStudio)
        ? StudioResponseBank.pageCopy(prompt)
        : null;

    Uint8List? audioWav;
    var audioLabel = 'Soundtrack';
    if (contributors.contains(StudioType.musicStudio)) {
      audioWav = AudioSynthService.synthesizeWav(
          seed: seed, durationSec: 20, bpm: 100, speechLike: false);
      audioLabel = 'Soundtrack';
    } else if (contributors.contains(StudioType.voiceAvatarStudio)) {
      audioWav = AudioSynthService.synthesizeWav(
          seed: seed, durationSec: 8, bpm: 100, speechLike: true);
      audioLabel = 'Voiceover';
    }

    Uint8List? videoPoster;
    if (contributors.contains(StudioType.videoStudio)) {
      videoPoster = await rasterizeGradientArt(seed: seed + 100);
    }

    return assemblePage(
      base,
      images: images,
      copy: copy,
      audioWav: audioWav,
      audioLabel: audioLabel,
      videoPoster: videoPoster,
      videoLabel: prompt,
      altText: prompt,
    );
  }

  /// Demo mode's images are painted from a seed rather than stored, so an
  /// [ImageResult] is a description of how to repaint one.
  static GeneratedImage _asGeneratedImage(ImageResult result) =>
      GeneratedImage(alt: result.prompt, seed: result.seed);

  /// Rasterizes the generated image to real PNG bytes and splices it into
  /// the target HTML artifact as a new version.
  Future<void> _composeImageIntoArtifact(
    StreamController<ChatEvent> controller,
    Artifact target,
    GeneratedImage image,
  ) async {
    final pngBytes = await _resolveImageBytes(image);
    if (pngBytes == null) return;
    final updatedHtml = applyGeneratedImage(target.latest.content, pngBytes,
        altText: image.alt);
    controller.add(
        ArtifactUpdated(target.withNewVersion(updatedHtml, DateTime.now())));
  }

  /// The bytes behind a [GeneratedImage] — the in-memory copy, the stored
  /// asset, or a repaint from the seed. Null when none of the three can.
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

  /// Synthesizes a WAV and splices a playable `<audio>` player into the target
  /// HTML artifact as a new version — the page's embedded soundtrack.
  Future<void> _composeAudioIntoArtifact(
    StreamController<ChatEvent> controller,
    Artifact target,
    String userInput,
  ) async {
    final wav = AudioSynthService.synthesizeWav(
      seed: StudioResponseBank.seedFromString(userInput),
      durationSec: 20,
      bpm: 100,
      speechLike: _wantsSpokenAudio(userInput),
    );
    final updatedHtml = embedAudioPlayer(target.latest.content, wav,
        label: _wantsSpokenAudio(userInput) ? 'Voiceover' : 'Soundtrack');
    controller.add(
        ArtifactUpdated(target.withNewVersion(updatedHtml, DateTime.now())));
  }

  /// Rasterizes a poster and splices a video block (poster + play badge +
  /// "Simulated video" caption) into the target HTML artifact as a new version.
  Future<void> _composeVideoIntoArtifact(
    StreamController<ChatEvent> controller,
    Artifact target,
    String userInput,
  ) async {
    final poster = await rasterizeGradientArt(
        seed: StudioResponseBank.seedFromString(userInput) + 100);
    final updatedHtml =
        embedVideoBlock(target.latest.content, poster, label: userInput);
    controller.add(
        ArtifactUpdated(target.withNewVersion(updatedHtml, DateTime.now())));
  }

  static bool _wantsSpokenAudio(String input) {
    final lower = input.toLowerCase();
    return lower.contains('voiceover') ||
        lower.contains('voice over') ||
        lower.contains('voice-over') ||
        lower.contains('narrat');
  }

  /// Code-routed turns also produce an artifact: a runnable HTML page for
  /// page-shaped prompts, otherwise the generated code file.
  ///
  /// [reviseTarget] carries the create-vs-revise decision made in `planTurn`
  /// (see `findRevisionTarget`) — when set, this turn is a change to that
  /// artifact and becomes a new version of it rather than a fresh one. The
  /// decision is deliberately *not* made here: this backend and the live one
  /// used to each guess at it and guess differently.
  ///
  /// A non-empty [pageContributors] means other studios ran alongside Code
  /// Studio on this same request — their outputs (photos, copy, an audio
  /// player, a video block) are woven into the page before the artifact is
  /// even created, rather than added in later turns.
  /// Returns a short phrase naming the edit that was applied when this turn
  /// revised an artifact, or null when it created one — or when it recognised
  /// no edit and deliberately emitted nothing. A version identical to the one
  /// before it is worse than no version: the panel's navigator would imply
  /// something changed.
  Future<String?> _emitCodeArtifact(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    StudioResult result, {
    Set<StudioType> pageContributors = const {},
    Artifact? reviseTarget,
    GeneratedImage? existingImage,
  }) async {
    // A turn that exists to put a picture on a page is a page, whatever the
    // rest of the sentence looks like.
    final wantsHtml = existingImage != null ||
        StudioDetection.wantsHtmlArtifact(userInput);
    final now = DateTime.now();

    if (reviseTarget != null) {
      if (reviseTarget.kind == ArtifactKind.html) {
        // Demo mode has no model, so it applies the handful of edits it can do
        // exactly — to the artifact's *current* content, so revisions build on
        // each other — and admits it when the request isn't one of them. It
        // used to rebuild the page from the template every time, which put the
        // request itself in the <h1> and threw away the previous version.
        final revision =
            applyMockRevision(reviseTarget.latest.content, userInput);
        if (revision == null) return null;
        controller.add(
            ArtifactUpdated(reviseTarget.withNewVersion(revision.html, now)));
        return revision.summary;
      }
      // A code artifact has no stable anchors to edit, so demo mode replaces it
      // with a freshly generated file — plausible for a simulation.
      final content = result is CodeResult ? result.code : userInput;
      controller.add(ArtifactUpdated(reviseTarget.withNewVersion(content, now)));
      return 'rewrote the file';
    }

    if (wantsHtml) {
      // The page is named the same way in both backends, and the page's own
      // <title>/<h1> use that name rather than quoting the request back.
      // The template names the page after the request, then the page is read
      // back for its name — so demo mode and live mode arrive at a title the
      // same way even though only one of them has a model.
      final title = titleFromRequest(userInput);
      var content = StudioResponseBank.htmlArtifactContent(title);
      if (pageContributors.isNotEmpty) {
        content = await _assembleMockPage(userInput, pageContributors);
      }
      // The image the user pointed at goes on the page they just asked for.
      if (existingImage != null) {
        final bytes = await _resolveImageBytes(existingImage);
        if (bytes != null) {
          content = existingImage.kind == GeneratedMediaKind.audio
              ? applyGeneratedAudio(content, bytes, label: existingImage.alt)
              : applyGeneratedImage(content, bytes, altText: existingImage.alt);
        }
      }
      controller.add(ArtifactCreated(Artifact(
        id: _uuid.v4(),
        conversationId: conversation.id,
        title: title,
        kind: ArtifactKind.html,
        versions: [
          ArtifactVersion(content: content, createdAt: now),
        ],
      )));
    } else if (result is CodeResult) {
      controller.add(ArtifactCreated(Artifact(
        id: _uuid.v4(),
        conversationId: conversation.id,
        title: result.filename,
        kind: ArtifactKind.code,
        language: result.language.toLowerCase(),
        versions: [
          ArtifactVersion(content: result.code, createdAt: now),
        ],
      )));
    }
    return null;
  }

  Future<void> _runWebSearch(
    StreamController<ChatEvent> controller,
    String userInput,
  ) async {
    final toolId = _uuid.v4();
    controller.add(ToolUseStarted(
      id: toolId,
      tool: 'web_search',
      label: 'Searching the web…',
    ));
    await _delay(900, 1600);
    final citations = StudioResponseBank.cannedCitations(userInput);
    controller.add(ToolUseFinished(
      id: toolId,
      detail: '${citations.length} sources',
    ));
    await _streamText(controller, StudioResponseBank.searchSummary(userInput));
    controller.add(CitationsReady(citations));
  }

  Future<void> _runDeepResearch(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
  ) async {
    controller.add(const DeepResearchProgress(stage: 'planning'));
    await _delay(700, 1200);

    final queries = [
      '${userInput.trim()} overview',
      '${userInput.trim()} recent developments',
    ];
    for (var round = 1; round <= queries.length; round++) {
      controller.add(DeepResearchProgress(
        stage: 'searching',
        round: round,
        query: queries[round - 1],
        sourceCount: 2 + round,
      ));
      await _delay(900, 1500);
    }

    controller.add(const DeepResearchProgress(stage: 'synthesizing'));
    await _delay(700, 1200);

    final citations = StudioResponseBank.cannedCitations(userInput);
    final topic = userInput.trim();
    final report = StringBuffer('# Research: $topic\n\n')
      ..writeln('_Simulated report — add an API key for live research._\n')
      ..writeln('## Findings\n')
      ..writeln('1. The topic splits into sub-questions, each searched in '
          'its own round [1].')
      ..writeln('2. Sources are collected per round and deduplicated [2].')
      ..writeln('3. The final report ships as this markdown artifact with '
          'numbered citations [3].\n')
      ..writeln('## Sources\n');
    for (var i = 0; i < citations.length; i++) {
      report.writeln('${i + 1}. [${citations[i].title}](${citations[i].url})');
    }
    controller.add(ArtifactCreated(Artifact(
      id: _uuid.v4(),
      conversationId: conversation.id,
      title: 'Research: $topic',
      kind: ArtifactKind.markdown,
      versions: [
        ArtifactVersion(content: report.toString(), createdAt: DateTime.now()),
      ],
    )));

    await _streamText(
      controller,
      'Simulated research complete — 2 rounds, ${citations.length} '
      'sources. The report artifact above shows exactly how a live run '
      'will read.',
    );
    controller.add(CitationsReady(citations));
  }

  Future<void> _streamThinking(
    StreamController<ChatEvent> controller,
    String text,
  ) async {
    // Coarser chunks than reply text — thinking streams fast.
    final words = text.split(' ');
    for (var i = 0; i < words.length; i += 4) {
      if (controller.isClosed) return;
      final chunk = words.skip(i).take(4).join(' ');
      controller.add(ThinkingDelta(i == 0 ? chunk : ' $chunk'));
      await Future.delayed(Duration(milliseconds: 30 + _random.nextInt(50)));
    }
  }

  Future<void> _streamText(
    StreamController<ChatEvent> controller,
    String text,
  ) async {
    final words = text.split(' ');
    for (var i = 0; i < words.length; i++) {
      if (controller.isClosed) return;
      final chunk = i == 0 ? words[i] : ' ${words[i]}';
      controller.add(MessageDelta(chunk));
      await Future.delayed(Duration(milliseconds: 18 + _random.nextInt(35)));
    }
  }

  Future<void> _delay(int minMs, int maxMs) =>
      Future.delayed(Duration(milliseconds: minMs + _random.nextInt(maxMs - minMs)));
}
