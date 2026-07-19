import 'dart:async';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../models/artifact.dart';
import '../models/attachment.dart';
import '../models/conversation.dart';
import '../models/studio_request.dart';
import '../models/studio_result.dart';
import '../models/studio_type.dart';
import '../models/usage_report.dart';
import 'chat_service.dart';
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
      final studio = structuredRequest?.studioType ??
          StudioResponseBank.detectStudio(userInput);

      var thinking = StudioResponseBank.thinkingText(studio, userInput);
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
      if (wantsResearch) {
        await _runDeepResearch(controller, conversation, userInput);
      } else if (studio == StudioType.middleware &&
          StudioResponseBank.wantsWebSearch(userInput)) {
        await _runWebSearch(controller, userInput);
      } else {
        await _runStudioFlow(
            controller, conversation, studio, userInput, structuredRequest);
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
  ) async {
    final introText = structuredRequest != null
        ? StudioResponseBank.routingIntro(studio, structuredRequest.summary)
        : StudioResponseBank.routingIntro(studio, userInput);

    await _streamText(controller, introText);

    if (studio == StudioType.middleware) return;

    await _delay(500, 1100);
    final result = structuredRequest != null
        ? StudioResponseBank.buildResult(structuredRequest)
        : StudioResponseBank.buildResultFromFreeform(studio, userInput);

    // Code output ships as an artifact (side panel), not an inline card —
    // the artifact IS the deliverable, with copy/download/versions there.
    if (studio == StudioType.codeStudio) {
      _emitCodeArtifact(controller, conversation, userInput, result);
    } else {
      controller.add(StudioResultReady(result));
    }

    final followUp = StudioResponseBank.studioFollowUp(studio);
    if (followUp.isNotEmpty) {
      await _streamText(controller, '\n\n$followUp');
    }
  }

  /// Code-routed turns also produce an artifact: a runnable HTML page for
  /// page-shaped prompts, otherwise the generated code file. A follow-up
  /// code prompt in a conversation that already has an artifact revises it
  /// (new version) instead of creating a fresh one — the artifacts model.
  void _emitCodeArtifact(
    StreamController<ChatEvent> controller,
    Conversation conversation,
    String userInput,
    StudioResult result,
  ) {
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
      controller.add(ArtifactCreated(Artifact(
        id: _uuid.v4(),
        conversationId: conversation.id,
        title: userInput.trim(),
        kind: ArtifactKind.html,
        versions: [
          ArtifactVersion(
            content: StudioResponseBank.htmlArtifactContent(userInput),
            createdAt: now,
          ),
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

    await _streamText(
      controller,
      'Here\'s a simulated deep-research summary of "${userInput.trim()}". '
      'In live mode this runs multiple real search rounds and synthesizes a '
      'cited report; the flow below is the exact shape that will take.\n\n'
      '**Key findings (simulated)**\n\n'
      '1. The topic breaks into a few clear sub-questions, each researched '
      'in its own round.\n'
      '2. Sources are collected per round and deduplicated.\n'
      '3. The final report arrives as a versioned artifact with numbered '
      'citations.',
    );
    controller.add(CitationsReady(
      StudioResponseBank.cannedCitations(userInput),
    ));
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
