import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/artifact.dart';
import '../models/attachment.dart';
import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/message_block.dart';
import '../models/studio_request.dart';
import '../services/chat_service.dart';
import '../services/persistence_service.dart';
import 'message_event_folding.dart';

const _uuid = Uuid();

/// Owns conversation history and drives the mock middleware AI. This is the
/// single source of truth the Chat screen renders from.
class ConversationStore extends ChangeNotifier {
  final ChatService chatService;
  final PersistenceService persistence;

  /// Called when a new artifact is created, so the UI can open the artifacts
  /// panel automatically — like Claude, the result just appears; you don't
  /// click anything.
  void Function(String artifactId)? onArtifactCreated;

  /// Called with the user's text after a genuine user turn finishes, so the
  /// app can extract durable facts into cross-chat memory.
  void Function(String userText)? onUserTurnComplete;

  List<Conversation> _conversations = [];
  String? _currentId;
  bool _isLoaded = false;

  /// The in-flight generation, if any. Cancelling this subscription is how
  /// the Stop button interrupts a streaming reply.
  StreamSubscription<ChatEvent>? _activeSub;
  String? _streamingConversationId;
  String? _streamingMessageId;

  ConversationStore({required this.chatService, required this.persistence});

  bool get isLoaded => _isLoaded;

  /// True while a reply is streaming into the *current* conversation, so the
  /// composer can swap its Send button for a Stop button.
  bool get isStreaming =>
      _activeSub != null && _streamingConversationId == _currentId;

  /// Interrupts the in-flight generation (the Stop button). The partial reply
  /// is kept and marked complete, exactly like Claude's stop.
  void stopGeneration() {
    final convId = _streamingConversationId;
    final msgId = _streamingMessageId;
    _activeSub?.cancel();
    _activeSub = null;
    _streamingConversationId = null;
    _streamingMessageId = null;
    if (convId != null && msgId != null) {
      _updateMessage(
        convId,
        msgId,
        (m) => m.status == MessageStatus.streaming
            ? m.copyWith(status: MessageStatus.complete)
            : m,
      );
      _persistConversation(convId);
    }
    notifyListeners();
  }

  List<Conversation> get conversations {
    final sorted = [..._conversations];
    sorted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted;
  }

  Conversation? get current {
    if (_currentId == null) return null;
    try {
      return _conversations.firstWhere((c) => c.id == _currentId);
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    _conversations = await persistence.loadConversations();
    if (conversations.isNotEmpty) {
      _currentId = conversations.first.id;
    }
    _isLoaded = true;
    notifyListeners();
  }

  void startNewConversation({String? projectId}) {
    final now = DateTime.now();
    final convo = Conversation(
      id: _uuid.v4(),
      title: 'New chat',
      createdAt: now,
      updatedAt: now,
      messages: const [],
      projectId: projectId,
    );
    _conversations.insert(0, convo);
    _currentId = convo.id;
    notifyListeners();
  }

  void renameConversation(String id, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return;
    _mutateConversation(id, (c) => c.copyWith(title: trimmed));
    _persistConversation(id);
  }

  void toggleStar(String id) {
    _mutateConversation(id, (c) => c.copyWith(starred: !c.starred));
    _persistConversation(id);
  }

  void togglePin(String id) {
    _mutateConversation(id, (c) => c.copyWith(pinned: !c.pinned));
    _persistConversation(id);
  }

  /// Archives (or unarchives) a conversation. Archiving the current chat
  /// moves selection to the next visible one.
  void toggleArchive(String id) {
    _mutateConversation(id, (c) => c.copyWith(archived: !c.archived));
    _persistConversation(id);
    if (_currentId == id && (current?.archived ?? false)) {
      final next = conversations.where((c) => !c.archived).toList();
      _currentId = next.isNotEmpty ? next.first.id : null;
      notifyListeners();
    }
  }

  void setConversationProject(String id, String? projectId) {
    _mutateConversation(id, (c) => c.copyWith(projectId: projectId));
    _persistConversation(id);
  }

  /// Case-insensitive search over titles and message text.
  List<Conversation> search(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return conversations;
    return conversations.where((c) {
      if (c.title.toLowerCase().contains(q)) return true;
      return c.messages.any((m) => m.text.toLowerCase().contains(q));
    }).toList();
  }

  /// Replaces a user message's text and replays the conversation from that
  /// point: everything from the edited message onward is dropped, then the
  /// new text is sent as a fresh turn.
  Future<void> editAndResend(
    String messageId,
    String newText, {
    ChatOptions options = ChatOptions.none,
  }) async {
    final convo = current;
    if (convo == null) return;
    final index = convo.messages.indexWhere((m) => m.id == messageId);
    if (index == -1 || convo.messages[index].role != MessageRole.user) return;

    _mutateConversation(convo.id, (c) {
      return c.copyWith(messages: c.messages.sublist(0, index));
    });
    await sendMessage(newText, options: options);
  }

  /// Re-runs the turn that produced [assistantMessageId], keeping the previous
  /// reply as a switchable variant (Claude's regenerate: the old answer isn't
  /// lost, it moves behind a ‹1/2› navigator). The new reply streams into the
  /// same message in place.
  Future<void> regenerate(
    String assistantMessageId, {
    ChatOptions options = ChatOptions.none,
  }) async {
    final convo = current;
    if (convo == null) return;
    final index =
        convo.messages.indexWhere((m) => m.id == assistantMessageId);
    if (index <= 0) return;
    final userMessage = convo.messages[index - 1];
    if (userMessage.role != MessageRole.user) return;
    final assistant = convo.messages[index];

    // Archive the current response, then clear the live fields so the fresh
    // reply streams in on top. activeVariant points at the new live entry.
    _updateMessage(convo.id, assistantMessageId, (m) {
      final archived = [...m.variants, m.toVariant()];
      return ChatMessage(
        id: m.id,
        conversationId: m.conversationId,
        role: m.role,
        text: '',
        blocks: const [],
        attachments: m.attachments,
        citations: const [],
        usage: null,
        studioType: m.studioType,
        studioResult: null,
        timestamp: m.timestamp,
        status: MessageStatus.streaming,
        variants: archived,
        activeVariant: archived.length,
        feedback: MessageFeedback.none,
      );
    });

    await _streamReply(
      conversationId: convo.id,
      assistantMessageId: assistant.id,
      userInput: userMessage.text,
      options: options,
    );
  }

  /// Picks up a reply that was cut off at the token ceiling (Claude's
  /// "Continue"). The existing text is kept and the model streams more onto the
  /// end of the same message — the deltas append in place.
  Future<void> continueReply(
    String messageId, {
    ChatOptions options = ChatOptions.none,
  }) async {
    final convo = current;
    if (convo == null) return;
    final index = convo.messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final message = convo.messages[index];
    if (message.status != MessageStatus.incomplete) return;

    // Flip back to streaming; new deltas fold onto the existing text/blocks.
    _updateMessage(convo.id, messageId, (m) {
      return m.copyWith(status: MessageStatus.streaming);
    });

    await _streamReply(
      conversationId: convo.id,
      assistantMessageId: messageId,
      userInput: 'Continue exactly where you left off, without repeating '
          'anything you already wrote.',
      options: options,
    );
  }

  /// Switches which stored response is shown for [messageId] (the ‹1/2›
  /// navigator). [index] is clamped to the available responses.
  void selectVariant(String messageId, int index) {
    final convo = current;
    if (convo == null) return;
    _updateMessage(convo.id, messageId, (m) {
      final clamped = index.clamp(0, m.variantCount - 1);
      return m.copyWith(activeVariant: clamped);
    });
    _persistConversation(convo.id);
  }

  /// Records thumbs up/down on an assistant reply (toggles off if repeated).
  void setFeedback(String messageId, MessageFeedback feedback) {
    final convo = current;
    if (convo == null) return;
    _updateMessage(convo.id, messageId, (m) {
      final next = m.feedback == feedback ? MessageFeedback.none : feedback;
      return m.copyWith(feedback: next);
    });
    _persistConversation(convo.id);
  }

  void selectConversation(String id) {
    _currentId = id;
    notifyListeners();
  }

  void deleteConversation(String id) {
    _conversations.removeWhere((c) => c.id == id);
    if (_currentId == id) {
      _currentId = _conversations.isNotEmpty ? conversations.first.id : null;
    }
    notifyListeners();
    persistence.deleteConversation(id);
  }

  void clearAllHistory() {
    _conversations = [];
    _currentId = null;
    notifyListeners();
    persistence.saveConversations(const []);
  }

  Future<void> sendMessage(
    String text, {
    StudioRequest? structuredRequest,
    List<Attachment> attachments = const [],
    ChatOptions options = ChatOptions.none,
  }) async {
    final displayText = structuredRequest?.summary ?? text;
    if (displayText.trim().isEmpty && attachments.isEmpty) return;

    if (current == null) {
      startNewConversation();
    }
    final conversationId = _currentId!;

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      conversationId: conversationId,
      role: MessageRole.user,
      text: displayText,
      attachments: attachments,
      studioType: structuredRequest?.studioType,
      timestamp: DateTime.now(),
    );

    final assistantMessage = ChatMessage(
      id: _uuid.v4(),
      conversationId: conversationId,
      role: MessageRole.assistant,
      text: '',
      timestamp: DateTime.now(),
      status: MessageStatus.streaming,
    );

    _mutateConversation(conversationId, (convo) {
      final messages = [...convo.messages, userMessage, assistantMessage];
      var title = convo.title;
      if (title == 'New chat') {
        title = displayText.length > 40
            ? '${displayText.substring(0, 40)}…'
            : displayText;
      }
      return convo.copyWith(
        messages: messages,
        title: title,
        updatedAt: DateTime.now(),
      );
    });

    return _streamReply(
      conversationId: conversationId,
      assistantMessageId: assistantMessage.id,
      userInput: text,
      structuredRequest: structuredRequest,
      attachments: attachments,
      options: options,
      extractMemory: true,
    );
  }

  /// Streams a reply from the chat service into the existing (empty, streaming)
  /// assistant message [assistantMessageId]. Shared by [sendMessage] and
  /// [regenerate]. Returns when the stream ends (or is stopped).
  Future<void> _streamReply({
    required String conversationId,
    required String assistantMessageId,
    required String userInput,
    StudioRequest? structuredRequest,
    List<Attachment> attachments = const [],
    ChatOptions options = ChatOptions.none,
    bool extractMemory = false,
  }) async {
    // Cancel any prior in-flight generation before starting a new one.
    await _activeSub?.cancel();

    final stream = chatService.sendMessage(
      conversation: current!,
      userInput: userInput,
      structuredRequest: structuredRequest,
      attachments: attachments,
      options: options,
    );

    final completer = Completer<void>();
    _streamingConversationId = conversationId;
    _streamingMessageId = assistantMessageId;
    void finish() {
      _activeSub = null;
      _streamingConversationId = null;
      _streamingMessageId = null;
      if (extractMemory) onUserTurnComplete?.call(userInput);
      notifyListeners();
      if (!completer.isCompleted) completer.complete();
    }

    _activeSub = stream.listen(
      (event) => _handleStreamEvent(conversationId, assistantMessageId, event),
      onError: (Object error) {
        _updateMessage(
          conversationId,
          assistantMessageId,
          (m) => foldMessageEvent(m, MessageError('$error')),
        );
        _persistConversation(conversationId);
        finish();
      },
      onDone: finish,
    );
    // Let the composer switch to the Stop button right away.
    notifyListeners();
    return completer.future;
  }

  void _handleStreamEvent(
    String conversationId,
    String messageId,
    ChatEvent event,
  ) {
    switch (event) {
      case ArtifactCreated(:final artifact):
        _upsertArtifact(conversationId, messageId, artifact);
        // Interactive results (recipe/quiz/…) render inline in the chat, so
        // they don't take over the side panel; only website/app builds do.
        if (!artifact.interactive) onArtifactCreated?.call(artifact.id);
      case ArtifactUpdated(:final artifact):
        _upsertArtifact(conversationId, messageId, artifact);
        if (!artifact.interactive) onArtifactCreated?.call(artifact.id);
      case ImageGenerated(:final pngBytes, :final alt):
        // Bytes go to the asset store (IndexedDB) so the image survives
        // reload; the block keeps them in memory for immediate display.
        final assetId = _uuid.v4();
        persistence.saveAsset(assetId, pngBytes);
        _updateMessage(conversationId, messageId, (m) {
          return m.copyWith(blocks: [
            ...m.blocks,
            ImageBlock(alt: alt, pngBytes: pngBytes, assetId: assetId),
          ]);
        });
      case MessageComplete() || MessageError() || MessageIncomplete():
        _updateMessage(
          conversationId,
          messageId,
          (m) => foldMessageEvent(m, event),
        );
        _persistConversation(conversationId);
      default:
        _updateMessage(
          conversationId,
          messageId,
          (m) => foldMessageEvent(m, event),
        );
    }
  }

  /// Adds or replaces the artifact on the conversation and appends an
  /// [ArtifactRefBlock] to the streaming assistant message pointing at the
  /// artifact's newest version.
  void _upsertArtifact(
    String conversationId,
    String messageId,
    Artifact artifact,
  ) {
    _mutateConversation(conversationId, (convo) {
      final artifacts = [...convo.artifacts];
      final index = artifacts.indexWhere((a) => a.id == artifact.id);
      if (index == -1) {
        artifacts.add(artifact);
      } else {
        artifacts[index] = artifact;
      }
      return convo.copyWith(artifacts: artifacts);
    });
    _updateMessage(conversationId, messageId, (m) {
      final ref = ArtifactRefBlock(
        artifactId: artifact.id,
        title: artifact.title,
        kind: artifact.kind,
        versionIndex: artifact.versions.length - 1,
        interactive: artifact.interactive,
      );
      // If this message already points at the artifact (a new version arrived),
      // update that block in place rather than stacking a duplicate.
      final existing = m.blocks.indexWhere(
        (b) => b is ArtifactRefBlock && b.artifactId == artifact.id,
      );
      if (existing != -1) {
        final blocks = [...m.blocks];
        blocks[existing] = ref;
        return m.copyWith(blocks: blocks);
      }
      return m.copyWith(blocks: [...m.blocks, ref]);
    });
  }

  void _mutateConversation(
    String id,
    Conversation Function(Conversation) mutate,
  ) {
    final index = _conversations.indexWhere((c) => c.id == id);
    if (index == -1) return;
    _conversations[index] = mutate(_conversations[index]);
    notifyListeners();
  }

  void _updateMessage(
    String conversationId,
    String messageId,
    ChatMessage Function(ChatMessage) update,
  ) {
    _mutateConversation(conversationId, (convo) {
      final messages = convo.messages.map((m) {
        return m.id == messageId ? update(m) : m;
      }).toList();
      return convo.copyWith(messages: messages, updatedAt: DateTime.now());
    });
  }

  /// Saves just the mutated conversation, then trims history past the cap
  /// (oldest first) from both memory and storage.
  Future<void> _persistConversation(String id) async {
    final index = _conversations.indexWhere((c) => c.id == id);
    if (index == -1) return;
    await persistence.saveConversation(_conversations[index]);

    if (_conversations.length > PersistenceService.maxStoredConversations) {
      final sorted = conversations; // newest first
      final excess =
          sorted.skip(PersistenceService.maxStoredConversations).toList();
      for (final old in excess) {
        _conversations.removeWhere((c) => c.id == old.id);
        await persistence.deleteConversation(old.id);
      }
      notifyListeners();
    }
  }
}
