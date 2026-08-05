


import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/attachment.dart';
import '../../../data/stores/api_keys_store.dart';
import '../../../data/stores/conversation_store.dart';
import '../../../data/stores/memory_store.dart';
import '../../../data/stores/project_store.dart';
import '../../../data/stores/styles_store.dart';
import '../../../data/stores/usage_store.dart';
import '../../../data/stores/user_prefs_store.dart';
import '../live_voice_overlay.dart';
import '../voice_mode_overlay.dart';
import '../../../turn/chat_service.dart';
import '../../voice/live_voice_controller.dart';
import '../../../core/widgets/liquid_glass.dart';
import 'dart:async';
import 'composer_attachments.dart';
import 'composer_dictation.dart';
import 'composer_options.dart';
import '../../../data/stores/account_store.dart';
import '../../../turn/live_mode.dart';
import 'model_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'send_button.dart';
import 'stop_button.dart';


/// Claude-style composer: a single rounded card holding the text field with
/// a row of controls beneath it — an attach button, a model chip, and a
/// circular purple send button.

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}


class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  // The composer's three concerns, each owning its own state and lifecycle.
  final _attachments = ComposerAttachments();
  final _options = ComposerOptions();
  late final _dictation = ComposerDictation(_controller);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
    // Accept pasted screenshots and dropped files anywhere in the app (web).
    _attachments.startIntake(() {
      if (mounted) setState(() {});
    });
    // Enter sends; Shift+Enter inserts a newline (Claude's composer behavior).
    _focusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed) {
        _send();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
  }

  ChatOptions _buildOptions() => _options.build(
        prefs: context.read<UserPrefsStore>(),
        projects: context.read<ProjectStore>(),
        conversations: context.read<ConversationStore>(),
        memory: context.read<MemoryStore>(),
        styles: context.read<StylesStore>(),
      );

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.items.isEmpty) return;
    final store = context.read<ConversationStore>();
    if (store.current == null) {
      store.startNewConversation(
        projectId: context.read<ProjectStore>().activeProjectId,
      );
    }
    store.sendMessage(
      text,
      attachments: _attachments.snapshot(),
      options: _buildOptions(),
    );
    context.read<UsageStore>().recordMessage();
    _controller.clear();
    setState(_attachments.clear);
    _focusNode.requestFocus();
  }

  Future<void> _pickFiles() async {
    await _attachments.pickFiles();
    if (mounted) setState(() {});
  }

  void _toggleDictation() {
    if (!ComposerDictation.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Voice input isn\'t supported in this browser — try Chrome, '
            'Edge, or Safari.',
          ),
        ),
      );
      return;
    }
    final wasListening = _dictation.listening;
    _dictation.toggle(onChanged: () {
      if (mounted) setState(() {});
    });
    if (wasListening) _focusNode.requestFocus();
  }

  @override
  void dispose() {
    _attachments.dispose();
    _dictation.dispose();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LiquidGlass(
            borderRadius: BorderRadius.circular(24),
            blurSigma: 30,
            tintOpacity: 0.72,
            border: Border.all(
              color: _attachments.dragActive ? theme.colorScheme.primary : colors.border,
              width: _attachments.dragActive ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.brightness == Brightness.dark ? 0.35 : 0.06,
                ),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_attachments.items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(
                      left: AppSpacing.sm,
                      top: AppSpacing.sm,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final attachment in _attachments.items)
                            InputChip(
                              avatar: Icon(switch (attachment.kind) {
                                AttachmentKind.image => Icons.image_outlined,
                                AttachmentKind.pdf =>
                                  Icons.picture_as_pdf_outlined,
                                AttachmentKind.text =>
                                  Icons.description_outlined,
                              }, size: 15),
                              label: Text(
                                attachment.name,
                                style: theme.textTheme.labelSmall,
                              ),
                              visualDensity: VisualDensity.compact,
                              onDeleted: () => setState(
                                () => _attachments.items.remove(attachment),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 8,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    hintText: 'Message SHIFT AI…',
                    filled: false,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.md,
                    ),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Attach images, PDFs, or text files',
                      icon: const Icon(Icons.attach_file_rounded, size: 20),
                      color: colors.textSecondary,
                      onPressed: _pickFiles,
                    ),
                    ModelChip(
                      modelPin: _options.modelPin,
                      onSelected: (pin) => setState(() => _options.modelPin = pin),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: _dictation.listening
                          ? 'Stop dictation'
                          : 'Dictate your message',
                      icon: Icon(
                        _dictation.listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        size: 20,
                      ),
                      color: _dictation.listening
                          ? theme.colorScheme.primary
                          : colors.textSecondary,
                      onPressed: _toggleDictation,
                    ),
                    // Voice mode runs on the ordinary chat path, so it works
                    // with whichever provider has a key rather than only the
                    // one vendor with a realtime endpoint. Gemini's realtime
                    // session is still reachable from the same button when a
                    // Google key is present, since it is lower-latency.
                    Builder(
                      builder: (context) {
                        final keys = context.watch<ApiKeysStore>();
                        final live = keys.hasGeminiKey &&
                            LiveVoiceController.isSupported;
                        return IconButton(
                          tooltip: live
                              ? 'Realtime voice conversation'
                              : 'Voice mode — talk, and it answers out loud',
                          icon: const Icon(Icons.graphic_eq_rounded, size: 20),
                          color: theme.colorScheme.primary,
                          onPressed: () => live
                              ? showLiveVoiceOverlay(context, keys.geminiKey)
                              : showVoiceModeOverlay(context),
                        );
                      },
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Builder(
                      builder: (context) {
                        final streaming =
                            context.watch<ConversationStore>().isStreaming;
                        return streaming
                            ? StopButton(
                                onPressed: () => context
                                    .read<ConversationStore>()
                                    .stopGeneration(),
                              )
                            : SendButton(
                                enabled: _hasText || _attachments.items.isNotEmpty,
                                onPressed: _send,
                              );
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Only demo mode says anything under the composer. The live-mode
          // line and the usage bar were permanent furniture: a caution nobody
          // reads twice and a daily counter for a quota this app does not
          // enforce, both sitting under every message forever. Demo mode's
          // line earns its place — it says the answers are not real.
          if (describeLive(liveCapability(
                hasOwnKey: context.watch<ApiKeysStore>().isLive,
                hasMembership: context
                    .watch<AccountStore>()
                    .spendableProviders
                    .isNotEmpty,
              )).footer
              case final footer?) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                footer,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Model picker: Auto (the middleware routes each request) or a pinned
/// model that bypasses routing. Pins only matter in live mode, so the menu
/// lists Auto plus — for each provider the user has a key for — that
/// provider's chat models under a disabled header. New providers appear
/// automatically via the registry.
