import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/attachment.dart';
import 'dart:async';

import '../../screens/chat/live_voice_overlay.dart';
import '../../services/chat_service.dart';
import '../../services/live/live_voice_controller.dart';
import '../../services/prompt_assembler.dart';
import '../../services/providers/anthropic_api_config.dart';
import '../../services/speech/speech_service.dart';
import '../../state/api_keys_store.dart';
import '../../state/conversation_store.dart';
import '../../state/project_store.dart';
import '../../state/user_prefs_store.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

const _uuid = Uuid();

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
  final List<Attachment> _attachments = [];

  /// Exact model id pinned from the model chip; null = auto-route.
  String? _modelPin;

  bool _listening = false;
  StreamSubscription<SpeechResult>? _speechSubscription;
  String _textBeforeDictation = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final hasText = _controller.text.trim().isNotEmpty;
      if (hasText != _hasText) setState(() => _hasText = hasText);
    });
  }

  /// System prompt for this turn: the conversation's own project wins;
  /// otherwise the sidebar's active project applies (and scopes the new
  /// conversation).
  ChatOptions _buildOptions() {
    final prefs = context.read<UserPrefsStore>();
    final projects = context.read<ProjectStore>();
    final store = context.read<ConversationStore>();
    final project =
        projects.projectById(store.current?.projectId) ??
            projects.activeProject;
    return ChatOptions(
      modelPin: _modelPin,
      systemPrompt: assembleSystemPrompt(
        nickname: prefs.nickname,
        responseStyle: prefs.responseStyle,
        customInstructions: prefs.customInstructions,
        project: project,
      ),
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final store = context.read<ConversationStore>();
    if (store.current == null) {
      store.startNewConversation(
        projectId: context.read<ProjectStore>().activeProjectId,
      );
    }
    store.sendMessage(
      text,
      attachments: List.of(_attachments),
      options: _buildOptions(),
    );
    _controller.clear();
    setState(() => _attachments.clear());
    _focusNode.requestFocus();
  }

  Future<void> _pickFiles() async {
    const typeGroup = XTypeGroup(
      label: 'Images, PDFs & text',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'pdf', 'txt', 'md'],
    );
    final files = await openFiles(acceptedTypeGroups: const [typeGroup]);
    if (files.isEmpty) return;
    for (final file in files) {
      final bytes = await file.readAsBytes();
      final mimeType = file.mimeType ?? _mimeFromName(file.name);
      _attachments.add(Attachment(
        id: _uuid.v4(),
        name: file.name,
        mimeType: mimeType,
        kind: AttachmentKind.fromMimeType(mimeType),
        bytes: bytes,
      ));
    }
    if (mounted) setState(() {});
  }

  static String _mimeFromName(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'pdf' => 'application/pdf',
      _ => 'text/plain',
    };
  }

  void _toggleDictation() {
    if (!SpeechService.isSupported) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Voice input isn\'t supported in this browser — try Chrome, '
            'Edge, or Safari.'),
      ));
      return;
    }
    if (_listening) {
      SpeechService.stop();
      setState(() => _listening = false);
      return;
    }
    _textBeforeDictation =
        _controller.text.isEmpty ? '' : '${_controller.text.trimRight()} ';
    setState(() => _listening = true);
    _speechSubscription = SpeechService.listen().listen(
      (result) {
        _controller.text = _textBeforeDictation + result.transcript;
        _controller.selection = TextSelection.collapsed(
          offset: _controller.text.length,
        );
      },
      onDone: () {
        if (mounted) setState(() => _listening = false);
        _focusNode.requestFocus();
      },
    );
  }

  @override
  void dispose() {
    _speechSubscription?.cancel();
    SpeechService.stop();
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
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colors.border),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_attachments.isNotEmpty)
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
                          for (final attachment in _attachments)
                            InputChip(
                              avatar: Icon(
                                switch (attachment.kind) {
                                  AttachmentKind.image =>
                                    Icons.image_outlined,
                                  AttachmentKind.pdf =>
                                    Icons.picture_as_pdf_outlined,
                                  AttachmentKind.text =>
                                    Icons.description_outlined,
                                },
                                size: 15,
                              ),
                              label: Text(
                                attachment.name,
                                style: theme.textTheme.labelSmall,
                              ),
                              visualDensity: VisualDensity.compact,
                              onDeleted: () => setState(
                                () => _attachments.remove(attachment),
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
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
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
                    const SizedBox(width: AppSpacing.xs),
                    _ModelChip(
                      modelPin: _modelPin,
                      onSelected: (pin) => setState(() => _modelPin = pin),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: _listening
                          ? 'Stop dictation'
                          : 'Dictate your message',
                      icon: Icon(
                        _listening
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        size: 20,
                      ),
                      color: _listening
                          ? theme.colorScheme.primary
                          : colors.textSecondary,
                      onPressed: _toggleDictation,
                    ),
                    Builder(builder: (context) {
                      final keys = context.watch<ApiKeysStore>();
                      final enabled = keys.hasGeminiKey &&
                          LiveVoiceController.isSupported;
                      return IconButton(
                        tooltip: enabled
                            ? 'Live voice conversation (experimental)'
                            : 'Live voice (experimental) — needs a Google '
                                'key in Settings',
                        icon:
                            const Icon(Icons.graphic_eq_rounded, size: 20),
                        color: enabled
                            ? theme.colorScheme.primary
                            : colors.textSecondary
                                .withValues(alpha: 0.5),
                        onPressed: enabled
                            ? () => showLiveVoiceOverlay(
                                context, keys.geminiKey)
                            : null,
                      );
                    }),
                    const SizedBox(width: AppSpacing.xs),
                    _SendButton(enabled: _hasText, onPressed: _send),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.watch<ApiKeysStore>().isLive
                ? 'Live mode — SHIFT AI can make mistakes. Usage bills to '
                    'your API key.'
                : 'SHIFT AI is in demo mode — responses are simulated.',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Model picker: Auto (the middleware routes each request) or a pinned
/// model that bypasses routing. Pins only matter in live mode; the mock
/// ignores them.
class _ModelChip extends StatelessWidget {
  final String? modelPin;
  final ValueChanged<String?> onSelected;

  const _ModelChip({required this.modelPin, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final label = modelPin == null
        ? 'Auto'
        : AnthropicApiConfig.displayName(modelPin!);

    return PopupMenuButton<String>(
      tooltip: 'Choose a model — Auto lets the middleware AI route each '
          'request.',
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      onSelected: (value) => onSelected(value == 'auto' ? null : value),
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'auto',
          checked: modelPin == null,
          child: const Text('Auto (recommended)'),
        ),
        for (final model in AnthropicApiConfig.availableModels)
          CheckedPopupMenuItem(
            value: model,
            checked: modelPin == model,
            child: Text(AnthropicApiConfig.displayName(model)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 5,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.expand_more_rounded,
              size: 14,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const _SendButton({required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.4,
      duration: const Duration(milliseconds: 120),
      child: SizedBox(
        width: 34,
        height: 34,
        child: IconButton.filled(
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
