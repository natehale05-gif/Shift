import '../data/models/project.dart';
import 'choice_parsing.dart';

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

  buffer.write('\n\n$choiceInstruction');

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

/// The audio counterpart. Without it the model reaches for the browser's
/// speech-synthesis API and writes a page that reads the script aloud in a
/// robot voice — instead of the recording the user just generated.
const String existingAudioInstruction =
    'The user already generated audio earlier in this conversation and wants '
    'it on this page. Write an <audio controls> element with '
    'src="{{shift:audio}}" — that exact placeholder — and lay the page out '
    'around it. The app replaces the placeholder with the real recording. Do '
    'not use speechSynthesis or any text-to-speech API, do not invent a '
    'filename, do not ask the user to save a file, and do not say you are '
    'unable to include the audio.';

/// Appended when the page being written should carry an image the user already
/// generated in this conversation.
///
/// A generated image is a block in the transcript, not something sent back up
/// with the next request, so the model genuinely cannot see it. Told nothing,
/// it does the reasonable thing with what it knows: apologizes that it cannot
/// embed a photo, invents a filename, draws an SVG stand-in, and asks the user
/// to save a file next to a page that has no "next to". The app has the bytes
/// and substitutes them — the model's job is only to say where they go.
const String existingImageInstruction =
    'The user already generated an image earlier in this conversation and '
    'wants it on this page. Write the <img> tag with src="{{shift:image}}" — '
    'that exact placeholder — and style and place it as you see fit. The app '
    'replaces the placeholder with the real image. Do not invent a filename, '
    'do not ask the user to save a file, do not draw a substitute in SVG, and '
    'do not say you are unable to include the image.';

/// [systemPrompt] with the code-turn instructions appended. Null and empty
/// prompts are handled, since a turn with no personalization still needs them.
String? systemPromptForCodeTurn(
  String? systemPrompt, {
  required bool isCode,
  bool hasGeneratedImage = false,
  bool hasGeneratedAudio = false,
}) {
  if (!isCode) return systemPrompt;
  final parts = [
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty)
      systemPrompt.trim(),
    codeArtifactInstruction,
    if (hasGeneratedImage) existingImageInstruction,
    if (hasGeneratedAudio) existingAudioInstruction,
  ];
  return parts.join('\n\n');
}
