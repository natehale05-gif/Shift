import '../../../data/stores/conversation_store.dart';
import '../../../data/stores/memory_store.dart';
import '../../../data/stores/project_store.dart';
import '../../../data/stores/styles_store.dart';
import '../../../data/stores/user_prefs_store.dart';
import '../../../turn/chat_service.dart';
import '../../../turn/prompt_assembler.dart';

/// The per-turn choices the composer collects — model pin and the tool
/// toggles — plus the rule for turning them into [ChatOptions].
///
/// Kept out of the composer widget deliberately: [build] resolves the active
/// writing style (built-in or custom) and assembles the system prompt, and that
/// logic is worth testing on its own rather than only through a pumped widget.
///
/// The style is not among the per-turn choices: it is a standing preference set
/// in Settings, not something to re-pick on every message.
class ComposerOptions {
  /// Exact model id pinned from the model chip; null = auto-route.
  String? modelPin;

  // No tool toggles. Web search, code execution and extended thinking are
  // offered to the model on every turn and it reaches for them when the
  // answer needs them; deep research is selected by asking for a researched
  // report. A toggle asked people to predict, before writing the message,
  // whether the answer would need fresh information — which nobody knows in
  // advance, so they stayed off and the tools went unused.

  /// Builds the options for one turn.
  ///
  /// The system prompt follows the same precedence the UI implies: the
  /// conversation's own project wins; otherwise the sidebar's active project
  /// applies.
  ///
  /// [prefs.responseStyle] holds a style id — built-in or custom, the same
  /// shape either way — so resolving it is one lookup with nothing to tell
  /// apart. An id nothing answers to (a style deleted while selected) yields
  /// no instruction, which is Normal.
  ChatOptions build({
    required UserPrefsStore prefs,
    required ProjectStore projects,
    required ConversationStore conversations,
    required MemoryStore memory,
    required StylesStore styles,
  }) {
    final project = projects.projectById(conversations.current?.projectId) ??
        projects.activeProject;
    final style = styles.styleById(prefs.responseStyle);
    return ChatOptions(
      modelPin: modelPin,
      systemPrompt: assembleSystemPrompt(
        nickname: prefs.nickname,
        role: prefs.role,
        traits: prefs.traits,
        styleInstruction: style?.instructions ?? '',
        customInstructions: prefs.customInstructions,
        project: project,
        memories: memory.activeTexts,
      ),
    );
  }
}
