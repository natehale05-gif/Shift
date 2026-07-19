import '../models/project.dart';

/// Budget for inlined project knowledge, in characters — roughly 4k tokens.
/// Real providers get the same assembled prompt, so the budget applies
/// everywhere.
const int knowledgeCharBudget = 16000;

/// Builds the system prompt for one turn from the layered context: base
/// persona + the user's global preferences + the active project's
/// instructions and knowledge. Pure function — used identically by the mock
/// and (later) the real provider clients, and unit-tested as data-in
/// data-out.
String assembleSystemPrompt({
  String? nickname,
  String responseStyle = 'balanced',
  String customInstructions = '',
  Project? project,
}) {
  final buffer = StringBuffer(
    'You are SHIFT AI, a middleware AI that routes requests to specialized '
    'creation studios (image, video, voice, music, copy, code) and answers '
    'directly when no studio fits.',
  );

  if (nickname != null && nickname.trim().isNotEmpty) {
    buffer.write('\n\nAddress the user as "${nickname.trim()}".');
  }

  switch (responseStyle) {
    case 'concise':
      buffer.write('\n\nKeep responses short and direct.');
    case 'detailed':
      buffer.write(
          '\n\nGive thorough, well-structured responses with reasoning.');
    default:
      break; // balanced: no extra instruction
  }

  if (customInstructions.trim().isNotEmpty) {
    buffer.write(
        '\n\nThe user\'s standing instructions:\n${customInstructions.trim()}');
  }

  if (project != null) {
    buffer.write('\n\nActive project: "${project.name}".');
    if (project.customInstructions.trim().isNotEmpty) {
      buffer.write(
          '\nProject instructions:\n${project.customInstructions.trim()}');
    }
    if (project.knowledge.isNotEmpty) {
      buffer.write('\nProject knowledge:');
      var used = 0;
      for (final doc in project.knowledge) {
        final remaining = knowledgeCharBudget - used;
        if (remaining <= 0) {
          buffer.write('\n[Further knowledge documents omitted for length.]');
          break;
        }
        final text = doc.text.length > remaining
            ? '${doc.text.substring(0, remaining)}…'
            : doc.text;
        buffer.write('\n--- ${doc.name} ---\n$text');
        used += text.length;
      }
    }
  }

  return buffer.toString();
}
