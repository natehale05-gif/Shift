import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/conversation.dart';
import '../models/studio_request.dart';
import '../services/chat_service.dart';
import '../services/persistence_service.dart';

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

  void startNewConversation() {
    final now = DateTime.now();
    final convo = Conversation(
      id: _uuid.v4(),
      title: 'New chat',
      createdAt: now,
      updatedAt: now,
      messages: const [],
    );
    _conversations.insert(0, convo);
    _currentId = convo.id;
    notifyListeners();
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
    _persist();
  }

  void clearAllHistory() {
    _conversations = [];
    _currentId = null;
    notifyListeners();
    _persist();
  }

  Future<void> sendMessage(
    String text, {
    StudioRequest? structuredRequest,
  }) async {
    final displayText = structuredRequest?.summary ?? text;
    if (displayText.trim().isEmpty) return;

    if (current == null) {
      startNewConversation();
    }
    final conversationId = _currentId!;

    final userMessage = ChatMessage(
      id: _uuid.v4(),
      conversationId: conversationId,
      role: MessageRole.user,
      text: displayText,
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
    );

    await for (final event in stream) {
      switch (event) {
        case RoutingDetected(:final studioType):
          _updateMessage(
            conversationId,
            assistantMessage.id,
            (m) => m.copyWith(studioType: studioType),
          );
        case MessageDelta(:final chunk):
          _updateMessage(
            conversationId,
            assistantMessage.id,
            (m) => m.copyWith(text: m.text + chunk),
          );
        case StudioResultReady(:final result):
          _updateMessage(
            conversationId,
            assistantMessage.id,
            (m) => m.copyWith(studioResult: result),
          );
        case MessageComplete():
          _updateMessage(
            conversationId,
            assistantMessage.id,
            (m) => m.copyWith(status: MessageStatus.complete),
          );
          _persist();
        case MessageError(:final message):
          _updateMessage(
            conversationId,
            assistantMessage.id,
            (m) => m.copyWith(
              text: m.text.isEmpty ? 'Something went wrong: $message' : m.text,
              status: MessageStatus.error,
            ),
          );
          _persist();
      }
    }
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

  Future<void> _persist() => persistence.saveConversations(_conversations);
}
