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

  List<Conversation> _conversations = [];
  String? _currentId;
  bool _isLoaded = false;

  ConversationStore({required this.chatService, required this.persistence});

  bool get isLoaded => _isLoaded;

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

  /// Re-runs the turn that produced [assistantMessageId]: the assistant
  /// reply (and its user prompt) are removed and the prompt is sent again.
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

    _mutateConversation(convo.id, (c) {
      return c.copyWith(messages: c.messages.sublist(0, index - 1));
    });
    await sendMessage(userMessage.text, options: options);
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

    final stream = chatService.sendMessage(
      conversation: current!,
      userInput: text,
      structuredRequest: structuredRequest,
      attachments: attachments,
      options: options,
    );

    await for (final event in stream) {
      switch (event) {
        case ArtifactCreated(:final artifact):
          _upsertArtifact(conversationId, assistantMessage.id, artifact);
        case ArtifactUpdated(:final artifact):
          _upsertArtifact(conversationId, assistantMessage.id, artifact);
        case ImageGenerated(:final pngBytes, :final alt):
          // Bytes go to the asset store (IndexedDB) so the image survives
          // reload; the block keeps them in memory for immediate display.
          final assetId = _uuid.v4();
          persistence.saveAsset(assetId, pngBytes);
          _updateMessage(conversationId, assistantMessage.id, (m) {
            return m.copyWith(blocks: [
              ...m.blocks,
              ImageBlock(alt: alt, pngBytes: pngBytes, assetId: assetId),
            ]);
          });
        case MessageComplete() || MessageError():
          _updateMessage(
            conversationId,
            assistantMessage.id,
            (m) => foldMessageEvent(m, event),
          );
          _persistConversation(conversationId);
        default:
          _updateMessage(
            conversationId,
            assistantMessage.id,
            (m) => foldMessageEvent(m, event),
          );
      }
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
      return m.copyWith(blocks: [
        ...m.blocks,
        ArtifactRefBlock(
          artifactId: artifact.id,
          title: artifact.title,
          kind: artifact.kind,
          versionIndex: artifact.versions.length - 1,
        ),
      ]);
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
