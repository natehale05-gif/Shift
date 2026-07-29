import '../data/models/project.dart';

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
  String role = '',
  String traits = '',
  String responseStyle = 'normal',
  String styleInstruction = '',
  String customInstructions = '',
  Project? project,
  List<String> memories = const [],
}) {
  final buffer = StringBuffer(
    'You are SHIFT AI, a middleware AI that routes requests to specialized '
    'creation studios (image, video, voice, music, copy, code) and answers '
    'directly when no studio fits. When a request is missing details you '
    'genuinely need to do good work — tone, platform, length, language, '
    'style, or similar — ask a brief clarifying question before proceeding '
    'instead of guessing silently, the way a thoughtful collaborator would. '
    'Don\'t interrogate simple requests that are already clear; ask only '
    'when the missing detail would meaningfully change the result.',
  );

  if (nickname != null && nickname.trim().isNotEmpty) {
    buffer.write('\n\nAddress the user as "${nickname.trim()}".');
  }

  if (role.trim().isNotEmpty) {
    buffer.write('\n\nThe user\'s role / what they do: ${role.trim()}. '
        'Tailor examples and depth to this.');
  }

  if (traits.trim().isNotEmpty) {
    buffer.write('\n\nTraits SHIFT AI should have: ${traits.trim()}.');
  }

  // A custom style's own instructions take precedence over the built-in set.
  if (styleInstruction.trim().isNotEmpty) {
    buffer.write('\n\nStyle: ${styleInstruction.trim()}');
  } else {
    switch (responseStyle) {
      case 'concise':
        buffer.write('\n\nStyle: keep responses short and direct — lead with '
            'the answer, minimal preamble.');
      case 'explanatory':
        buffer.write('\n\nStyle: give thorough, well-structured responses that '
            'teach — explain the reasoning and include helpful examples.');
      case 'formal':
        buffer.write('\n\nStyle: write in a polished, professional register — '
            'complete sentences, no slang or emoji.');
      default:
        break; // normal: no extra instruction
    }
  }

  if (customInstructions.trim().isNotEmpty) {
    buffer.write(
        '\n\nThe user\'s standing instructions:\n${customInstructions.trim()}');
  }

  if (memories.isNotEmpty) {
    buffer.write('\n\nWhat you remember about the user from past chats '
        '(use naturally; don\'t recite):');
    for (final memory in memories) {
      final m = memory.trim();
      if (m.isNotEmpty) buffer.write('\n- $m');
    }
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

/// Appended to the system prompt on a code-routed turn, for every provider.
///
/// The reply's first substantial fenced block becomes the artifact the user
/// edits, previews and downloads, so the shape of the reply is load-bearing:
/// a page split across several fences, or wrapped in a fence that also holds
/// commentary, yields a broken artifact. Claude tends to answer this way
/// unprompted; saying it out loud makes every other provider's output usable
/// too.
const String codeArtifactInstruction =
    'Put the complete file in a single fenced code block, tagged with its '
    'language (```html for a web page). One block per reply — no partial '
    'snippets, no splitting a file across several blocks. Keep any '
    'explanation outside the block, and keep it short.';

/// [systemPrompt] with the code-artifact instruction appended when this turn
/// is code-routed. Null and empty prompts are handled, since a turn with no
/// personalization still needs the instruction.
String? systemPromptForCodeTurn(String? systemPrompt, {required bool isCode}) {
  if (!isCode) return systemPrompt;
  final base = systemPrompt?.trim() ?? '';
  return base.isEmpty
      ? codeArtifactInstruction
      : '$base\n\n$codeArtifactInstruction';
}
