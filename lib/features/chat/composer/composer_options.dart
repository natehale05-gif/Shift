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

  // Tool toggles (mirror Claude's tools/plus menu). All feed the per-turn
  // ChatOptions and drive real behaviour in both live and demo modes.
  bool webSearch = false;
  bool deepResearch = false;
  bool codeExecution = false;
  bool extendedThinking = true;

  /// Builds the options for one turn.
  ///
  /// The system prompt follows the same precedence the UI implies: the
  /// conversation's own project wins; otherwise the sidebar's active project
  /// applies. A *custom* style passes its instructions through
  /// `styleInstruction` and reports itself as 'normal', so a user-authored
  /// style overrides the built-in clauses rather than stacking with them.
  ///
  /// [prefs.responseStyle] holds a built-in id or a custom style's id — both
  /// come from the same Settings control, so there is one place a style is
  /// chosen and one value to resolve here.
  ChatOptions build({
    required UserPrefsStore prefs,
    required ProjectStore projects,
    required ConversationStore conversations,
    required MemoryStore memory,
    required StylesStore styles,
  }) {
    final project = projects.projectById(conversations.current?.projectId) ??
        projects.activeProject;
    final styleId = prefs.responseStyle;
    final customStyle = styles.styleById(styleId);
    return ChatOptions(
      modelPin: modelPin,
      webSearch: webSearch,
      deepResearch: deepResearch,
      codeExecution: codeExecution,
      extendedThinking: extendedThinking,
      systemPrompt: assembleSystemPrompt(
        nickname: prefs.nickname,
        role: prefs.role,
        traits: prefs.traits,
        responseStyle: customStyle == null ? styleId : 'normal',
        styleInstruction: customStyle?.instructions ?? '',
        customInstructions: prefs.customInstructions,
        project: project,
        memories: memory.activeTexts,
      ),
    );
  }
}
