import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../models/attachment.dart';
import '../../models/studio_type.dart';
import '../../services/chat_service.dart';
import '../../services/prompt_assembler.dart';
import '../../services/providers/anthropic_api_config.dart';
import '../../state/api_keys_store.dart';
import '../../state/conversation_store.dart';
import '../../state/project_store.dart';
import '../../state/user_prefs_store.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';
import 'studio_request_sheets.dart';

const _uuid = Uuid();

/// Claude-style composer: a single rounded card holding the text field with
/// a row of controls beneath it — studios behind the "+" menu, a model chip,
/// and a circular purple send button.
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
  bool _webSearchEnabled = false;
  bool _codeExecutionEnabled = false;

  static const _studios = [
    StudioType.imageStudio,
    StudioType.videoStudio,
    StudioType.voiceAvatarStudio,
    StudioType.musicStudio,
    StudioType.copyScriptsStudio,
    StudioType.codeStudio,
  ];

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
      webSearch: _webSearchEnabled,
      codeExecution: _codeExecutionEnabled,
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

  Future<void> _openStudioSheet(StudioType studioType) async {
    final request = await showStudioRequestSheet(context, studioType);
    if (request == null || !mounted) return;
    context
        .read<ConversationStore>()
        .sendMessage('', structuredRequest: request);
  }

  @override
  void dispose() {
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
                    _StudioMenuButton(onSelected: _openStudioSheet),
                    IconButton(
                      tooltip: 'Attach images, PDFs, or text files',
                      icon: const Icon(Icons.attach_file_rounded, size: 20),
                      color: colors.textSecondary,
                      onPressed: _pickFiles,
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Tools',
                      position: PopupMenuPosition.over,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusMd),
                      ),
                      icon: Icon(
                        Icons.tune_rounded,
                        size: 20,
                        color: _webSearchEnabled || _codeExecutionEnabled
                            ? theme.colorScheme.primary
                            : colors.textSecondary,
                      ),
                      onSelected: (value) => setState(() {
                        if (value == 'web') {
                          _webSearchEnabled = !_webSearchEnabled;
                        } else if (value == 'code') {
                          _codeExecutionEnabled = !_codeExecutionEnabled;
                        }
                      }),
                      itemBuilder: (context) => [
                        CheckedPopupMenuItem(
                          value: 'web',
                          checked: _webSearchEnabled,
                          child: const Text('Web search'),
                        ),
                        CheckedPopupMenuItem(
                          value: 'code',
                          checked: _codeExecutionEnabled,
                          child: const Text('Run code (server)'),
                        ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    _ModelChip(
                      modelPin: _modelPin,
                      onSelected: (pin) => setState(() => _modelPin = pin),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Voice input — coming soon',
                      icon: const Icon(Icons.mic_none_rounded, size: 20),
                      color: colors.textSecondary,
                      onPressed: null,
                      disabledColor: colors.textSecondary.withValues(
                        alpha: 0.5,
                      ),
                    ),
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

/// The "+" menu: structured studio requests (attachments join this menu in a
/// later phase, matching the Claude composer's plus menu).
class _StudioMenuButton extends StatelessWidget {
  final ValueChanged<StudioType> onSelected;

  const _StudioMenuButton({required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppSemanticColors>()!;
    return PopupMenuButton<StudioType>(
      tooltip: 'Studios',
      position: PopupMenuPosition.over,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      icon: Icon(Icons.add_rounded, color: colors.textSecondary),
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final studio in _ChatInputBarState._studios)
          PopupMenuItem(
            value: studio,
            child: Row(
              children: [
                Icon(studio.icon, size: 18, color: studio.accent),
                const SizedBox(width: AppSpacing.md),
                Text(studio.shortName),
              ],
            ),
          ),
      ],
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
