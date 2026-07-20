import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/models/chat_message.dart';
import 'package:shift_ai/models/conversation.dart';
import 'package:shift_ai/models/studio_type.dart';
import 'package:shift_ai/services/studio_clarification.dart';

ChatMessage _msg({
  required String id,
  required MessageRole role,
  required String text,
  StudioType? studioType,
}) =>
    ChatMessage(
      id: id,
      conversationId: 'c1',
      role: role,
      text: text,
      studioType: studioType,
      timestamp: DateTime(2026, 7, 20),
    );

Conversation _withMessages(List<ChatMessage> messages) => Conversation(
      id: 'c1',
      title: 'x',
      createdAt: DateTime(2026, 7, 20),
      updatedAt: DateTime(2026, 7, 20),
      messages: messages,
    );

/// The trailing pair the store always appends before a ChatService sees
/// the conversation: this turn's own user echo + an empty streaming
/// placeholder for the reply.
List<ChatMessage> _trailingTurn(String newUserText) => [
      _msg(id: 'newUser', role: MessageRole.user, text: newUserText),
      _msg(id: 'newAssistant', role: MessageRole.assistant, text: ''),
    ];

void main() {
  test('finds a pending clarification when the prior reply asked a question',
      () {
    final conversation = _withMessages([
      _msg(
        id: 'u1',
        role: MessageRole.user,
        text: 'make me a logo',
      ),
      _msg(
        id: 'a1',
        role: MessageRole.assistant,
        text: "What's the subject or brand, and any color preferences?",
        studioType: StudioType.imageStudio,
      ),
      ..._trailingTurn('navy blue'),
    ]);

    final pending = findPendingClarification(conversation);
    expect(pending, isNotNull);
    expect(pending!.$1, StudioType.imageStudio);
    expect(pending.$2, 'make me a logo');
  });

  test('returns null when the prior reply was a resolved result, not a '
      'question', () {
    final conversation = _withMessages([
      _msg(id: 'u1', role: MessageRole.user, text: 'write a python function'),
      _msg(
        id: 'a1',
        role: MessageRole.assistant,
        text: 'Routing this to Code Studio to build it.',
        studioType: StudioType.codeStudio,
      ),
      ..._trailingTurn('now add error handling'),
    ]);

    expect(findPendingClarification(conversation), isNull);
  });

  test('returns null when the prior assistant turn was middleware chat', () {
    final conversation = _withMessages([
      _msg(id: 'u1', role: MessageRole.user, text: 'how are you?'),
      _msg(
        id: 'a1',
        role: MessageRole.assistant,
        text: 'Doing well — what can I help with?',
        studioType: StudioType.middleware,
      ),
      ..._trailingTurn('tell me a joke'),
    ]);

    expect(findPendingClarification(conversation), isNull);
  });

  test('returns null on a brand new conversation with too little history',
      () {
    expect(
      findPendingClarification(_withMessages(_trailingTurn('hello'))),
      isNull,
    );
    expect(findPendingClarification(_withMessages(const [])), isNull);
  });
}
