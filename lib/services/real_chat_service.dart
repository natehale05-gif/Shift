import 'dart:async';

import 'package:uuid/uuid.dart';

import '../models/artifact.dart';
import '../models/attachment.dart';
import '../models/conversation.dart';
import '../models/studio_request.dart';
import '../state/api_keys_store.dart';
import 'chat_service.dart';
import 'mock_chat_service.dart';
import 'providers/anthropic_api_config.dart';
import 'providers/anthropic_client.dart';
import 'providers/anthropic_tools.dart';
import 'router/model_router.dart';

const _uuid = Uuid();

/// Live-mode middleware: routes each message (LLM classifier with keyword
/// fallback), then executes on the best available provider. Routes no live
/// provider can serve yet (image/video/audio before a Gemini key exists)
/// fall back to the mock so the request still produces a useful, clearly
/// simulated result.
class RealChatService implements ChatService {
  final ApiKeysStore keys;
  final AnthropicClient _anthropic;
  final ModelRouter _router;
  final MockChatService _mockFallback;

  RealChatService({
    required this.keys,
    AnthropicClient? anthropicClient,
    ModelRouter? router,
    MockChatService? mockFallback,
  })  : _anthropic = anthropicClient ?? AnthropicClient(),
        _router = router ?? ModelRouter(client: anthropicClient),
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
      // Structured studio forms and deep research keep their existing
      // simulated flows until their live executors ship.
      if (structuredRequest != null || options.deepResearch) {
        await _delegateToMock(controller, conversation, userInput,
            structuredRequest, attachments, options);
        return;
      }

      final route = options.modelPin != null
          ? ChatRoute.chat // an explicit model pin bypasses routing
          : await _router.route(
              input: userInput,
              anthropicKey: keys.anthropicKey,
            );

      switch (route) {
        case ChatRoute.chat ||
              ChatRoute.code ||
              ChatRoute.writing ||
              ChatRoute.webSearch ||
              ChatRoute.deepResearch:
          await _runAnthropicChat(
              controller, conversation, userInput, attachments, options, route);
        case ChatRoute.imageGen || ChatRoute.video || ChatRoute.audio:
          // No live provider for these yet — simulate, and say so.
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
          final artifact =
              extractCodeArtifact(buffer.toString(), conversation.id);
          if (artifact != null) controller.add(ArtifactCreated(artifact));
        }
      }
      controller.add(event);
    }
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
    final service = keys.hasAnthropicKey ? real : mock;
    return service.sendMessage(
      conversation: conversation,
      userInput: userInput,
      structuredRequest: structuredRequest,
      attachments: attachments,
      options: options,
    );
  }
}
