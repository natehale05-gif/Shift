import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/artifact.dart';
import '../models/attachment.dart';
import '../models/conversation.dart';
import '../models/studio_request.dart';
import '../models/studio_result.dart';
import '../models/studio_type.dart';
import '../models/usage_report.dart';
import 'artifact_composition.dart';
import 'audio_synth_service.dart';
import 'chat_service.dart';
import 'interactive_artifacts.dart';
import 'procedural_art.dart';
import 'studio_clarification.dart';
import 'studio_composition.dart';
import 'studio_response_bank.dart';

const _uuid = Uuid();

/// Simulates the "middleware AI" that routes to specialized studio models.
/// Everything here is fabricated locally with artificial delay to mimic a
/// real streaming backend — no network calls. It deliberately exercises the
/// full [ChatEvent] vocabulary (thinking, tool use, citations, artifacts,
/// deep research) so every UI path works before any API key exists.
class MockChatService implements ChatService {
  final Random _random = Random();

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
      // A terse follow-up to our own clarifying question ("navy blue")
      // continues the same studio request rather than being reclassified
      // from scratch — the studio comes from that pending question, and
      // its answer merges into a complete prompt.
      final pending = structuredRequest == null
          ? findPendingClarification(conversation)
          : null;
      // One composition decision for the whole turn (see studio_composition).
      // pageAssembly = "build a website with photos" (Code + Image together);
      // editArtifact = "add a hero image to the website" (splice into an
      // existing artifact). Everything else is a single studio.
      final plan = (structuredRequest == null && pending == null)
          ? planComposition(conversation, userInput)
          : CompositionPlan.none;
      // Interactive artifacts (recipe cards, quizzes, flashcards, checklists)
      // are self-contained interactive widgets built by Code Studio.
      final interactive = (structuredRequest == null && pending == null)
          ? InteractiveArtifacts.detect(userInput)
          : null;
      final wantsBoth = plan.kind == CompositionKind.pageAssembly;
      final studio = interactive != null
          ? StudioType.codeStudio
          : wantsBoth
              ? StudioType.codeStudio
              : isCopyFed(plan.kind)
                  ? copyFedHost(plan.kind)
                  : isMediaPair(plan.kind)
                      ? mediaPairHost(plan.kind)
                      : (structuredRequest?.studioType ??
                          pending?.$1 ??
                          StudioResponseBank.detectStudio(userInput));
      final effectiveInput =
          pending != null ? '${pending.$2} $userInput'.trim() : userInput;

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

      final wantsResearch = options.deepResearch ||
          userInput.toLowerCase().contains('deep research');
      if (interactive != null) {
        await _runInteractive(controller, conversation, interactive, userInput);
      } else if (wantsResearch) {
        await _runDeepResearch(controller, conversation, userInput);
      } else if (studio == StudioType.middleware &&
          (options.webSearch ||
              StudioResponseBank.wantsWebSearch(userInput))) {
        await _runWebSearch(controller, userInput);
      } else if (isCopyFed(plan.kind)) {
        await _runCopyFedMedia(controller, plan.kind, effectiveInput);
      } else if (isMediaPair(plan.kind)) {
        await _runMediaPair(controller, plan.kind, effectiveInput);
      } else if (studio == StudioType.avatarStudio) {
        // The Avatar studio is a talking-head: a portrait + a voiceover card
        // (a real Heygen video takes a key, wired in the live service).
        await _runMediaPair(
            controller, CompositionKind.talkingAvatar, effectiveInput);
      } else {
        final composeTarget =
            plan.kind == CompositionKind.editArtifact ? plan.editTarget : null;
        final composeKind =
            plan.kind == CompositionKind.editArtifact ? plan.editKind : null;
        await _runStudioFlow(
          controller,
          conversation,
          studio,
          effectiveInput,
          structuredRequest,
          pending != null,
          composeTarget,
          composeKind,
          wantsBoth ? plan.contributors : const <StudioType>{},
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
  ) async {
    final contributorNames =
        pageContributors.map((s) => s.displayName).toList();
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

    // Ask before guessing, like Claude does — but only once per request;
    // a reply to our own question always proceeds straight to generating.
    // A compose-into-artifact request ("add a video to the website") already
    // carries enough intent, so it skips the question and embeds directly.
    if (structuredRequest == null &&
        !isAnsweringClarification &&
        composeTarget == null) {
      final question = StudioResponseBank.clarifyingQuestion(studio, userInput);
      if (question != null) {
        await _streamText(controller, '\n\n$question');
        return;
      }
    }

    await _delay(500, 1100);
    final result = structuredRequest != null
        ? StudioResponseBank.buildResult(structuredRequest)
        : StudioResponseBank.buildResultFromFreeform(studio, userInput);

    if (composeTarget != null) {
      // Two studios in one turn: a studio's output gets woven into the
      // artifact another studio already built, instead of standing alone.
      switch (composeKind ?? ArtifactMediaKind.image) {
        case ArtifactMediaKind.image:
          await _composeImageIntoArtifact(
              controller, composeTarget, result as ImageResult);
        case ArtifactMediaKind.audio:
          await _composeAudioIntoArtifact(controller, composeTarget, userInput);
        case ArtifactMediaKind.video:
          await _composeVideoIntoArtifact(controller, composeTarget, userInput);
      }
    } else if (studio == StudioType.codeStudio) {
      // Code output ships as an artifact (side panel), not an inline card —
      // the artifact IS the deliverable, with copy/download/versions there.
      await _emitCodeArtifact(controller, conversation, userInput, result,
          pageContributors: pageContributors);
    } else {
      controller.add(StudioResultReady(result));
    }

    final followUp = pageContributors.isNotEmpty
        ? StudioResponseBank.pageAssemblyFollowUp(contributorNames)
        : composeTarget != null
            ? StudioResponseBank.compositionFollowUp(composeTarget.title,
                composeKind ?? ArtifactMediaKind.image)
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
      InteractiveKind.recipe => InteractiveArtifacts.renderRecipe(
          InteractiveArtifacts.templatedRecipe(topic),
          heroImageDataUri: heroUri),
      InteractiveKind.quiz => InteractiveArtifacts.renderQuiz(
          InteractiveArtifacts.templatedQuiz(topic), '${_titleCase(topic)} Quiz'),
      InteractiveKind.flashcards => InteractiveArtifacts.renderFlashcards(
          InteractiveArtifacts.templatedFlashcards(topic), '${_titleCase(topic)} Flashcards'),
      InteractiveKind.checklist => InteractiveArtifacts.renderChecklist(
          InteractiveArtifacts.templatedChecklist(topic), _titleCase(topic)),
    };
    final title = switch (kind) {
      InteractiveKind.recipe => _titleCase(topic),
      InteractiveKind.quiz => '${_titleCase(topic)} Quiz',
      InteractiveKind.flashcards => '${_titleCase(topic)} Flashcards',
      InteractiveKind.checklist => _titleCase(topic),
    };
    controller.add(ArtifactCreated(InteractiveArtifacts.build(
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
    final base = StudioResponseBank.htmlArtifactContent(prompt);

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

  /// Rasterizes the generated image to real PNG bytes and splices it into
  /// the target HTML artifact as a new version.
  Future<void> _composeImageIntoArtifact(
    StreamController<ChatEvent> controller,
    Artifact target,
    ImageResult result,
  ) async {
    final pngBytes = await rasterizeGradientArt(seed: result.seed);
    final updatedHtml =
        embedImageAsHero(target.latest.content, pngBytes, altText: result.prompt);
    controller.add(
        ArtifactUpdated(target.withNewVersion(updatedHtml, DateTime.now())));
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
  /// page-shaped prompts, otherwise the generated code file. A follow-up
  /// code prompt in a conversation that already has an artifact revises it
  /// (new version) instead of creating a fresh one — the artifacts model.
  /// A non-empty [pageContributors] means other studios ran alongside Code
  /// Studio on this same request — their outputs (photos, copy, an audio
  /// player, a video block) are woven into the page before the artifact is
  /// even created, rather than added in later turns.
  Future<void> _emitCodeArtifact(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    StudioResult result, {
    Set<StudioType> pageContributors = const {},
  }) async {
    final wantsHtml = StudioResponseBank.wantsHtmlArtifact(userInput);
    final now = DateTime.now();

    final existing =
        conversation.artifacts.isNotEmpty ? conversation.artifacts.last : null;
    if (existing != null) {
      final content = existing.kind == ArtifactKind.html
          ? StudioResponseBank.htmlArtifactContent(
              '${existing.title} — revised')
          : (result is CodeResult ? result.code : userInput);
      controller.add(ArtifactUpdated(existing.withNewVersion(content, now)));
      return;
    }

    if (wantsHtml) {
      var content = StudioResponseBank.htmlArtifactContent(userInput);
      if (pageContributors.isNotEmpty) {
        content = await _assembleMockPage(userInput, pageContributors);
      }
      controller.add(ArtifactCreated(Artifact(
        id: _uuid.v4(),
        conversationId: conversation.id,
        title: userInput.trim(),
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
