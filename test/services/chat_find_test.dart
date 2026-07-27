import 'package:flutter_test/flutter_test.dart';
import 'package:shift_ai/data/models/chat_message.dart';
import 'package:shift_ai/services/chat_find.dart';

ChatMessage _msg(String id, MessageRole role, String text) => ChatMessage(
      id: id,
      conversationId: 'c1',
      role: role,
      text: text,
      timestamp: DateTime(2026, 7, 21),
    );

void main() {
  final messages = [
    _msg('1', MessageRole.user, 'Tell me about otters'),
    _msg('2', MessageRole.assistant, 'Otters are playful river mammals.'),
    _msg('3', MessageRole.user, 'And beavers?'),
    _msg('4', MessageRole.assistant, 'Beavers build dams.'),
  ];

  test('finds matching message indices case-insensitively', () {
    expect(findMatchingMessageIndices(messages, 'OTTER'), [0, 1]);
    expect(findMatchingMessageIndices(messages, 'dams'), [3]);
    expect(findMatchingMessageIndices(messages, 'nothing here'), isEmpty);
  });

  test('an empty query matches nothing', () {
    expect(findMatchingMessageIndices(messages, ''), isEmpty);
    expect(findMatchingMessageIndices(messages, '   '), isEmpty);
  });
}
