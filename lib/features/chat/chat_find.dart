import '../../data/models/chat_message.dart';

/// Indices of the [messages] whose visible text contains [query]
/// (case-insensitive). Pure so the in-chat find bar's matching is testable.
List<int> findMatchingMessageIndices(
  List<ChatMessage> messages,
  String query,
) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return const [];
  final matches = <int>[];
  for (var i = 0; i < messages.length; i++) {
    if (messages[i].displayText.toLowerCase().contains(q)) matches.add(i);
  }
  return matches;
}
