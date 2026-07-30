
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/attachment.dart';
import '../../../data/models/chat_message.dart';
import '../../../data/stores/conversation_store.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
import 'attachment_preview_dialog.dart';
import 'user_branch_nav.dart';
import '../../../core/theme/tap_targets.dart';

class UserBubble extends StatefulWidget {
  final ChatMessage message;

  const UserBubble({super.key, required this.message});

  @override
  State<UserBubble> createState() => _UserBubbleState();
}


class _UserBubbleState extends State<UserBubble> {
  bool _hovering = false;

  ChatMessage get message => widget.message;

  Future<void> _edit() async {
    final store = context.read<ConversationStore>();
    final controller = TextEditingController(text: message.text);
    final newText = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit message'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 2,
            maxLines: 8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save & resend'),
          ),
        ],
      ),
    );
    if (newText == null || newText.trim().isEmpty) return;
    // Everything after this message is replaced by the replayed turn.
    store.editAndResend(message.id, newText.trim());
  }

  void _previewAttachment(BuildContext context, Attachment attachment) {
    final persistence = context.read<ConversationStore>().persistence;
    showDialog<void>(
      context: context,
      builder: (_) => AttachmentPreviewDialog(
        attachment: attachment,
        persistence: persistence,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    // Is this message an edit-branch point? (Its preceding message is an
    // anchor with more than one stored tail.)
    final convo = context.watch<ConversationStore>().current;
    String? branchAnchor;
    var branchActive = 0;
    var branchCount = 0;
    if (convo != null) {
      final idx = convo.messages.indexWhere((m) => m.id == message.id);
      if (idx != -1) {
        final anchorId = idx == 0 ? '' : convo.messages[idx - 1].id;
        final set = convo.branches[anchorId];
        if (set != null && set.length > 1) {
          branchAnchor = anchorId;
          branchActive = set.active;
          branchCount = set.length;
        }
      }
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (branchAnchor != null)
            UserBranchNav(
              anchorId: branchAnchor,
              active: branchActive,
              count: branchCount,
            ),
          if (message.attachments.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Wrap(
                spacing: AppSpacing.xs,
                children: [
                  for (final attachment in message.attachments)
                    ActionChip(
                      avatar: Icon(
                        switch (attachment.kind) {
                          AttachmentKind.image => Icons.image_outlined,
                          AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
                          AttachmentKind.text => Icons.description_outlined,
                        },
                        size: 15,
                        color: colors.textSecondary,
                      ),
                      label: Text(
                        attachment.name,
                        style: theme.textTheme.labelSmall,
                      ),
                      visualDensity: touchSafeDensity,
                      onPressed: () =>
                          _previewAttachment(context, attachment),
                    ),
                ],
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedOpacity(
                opacity: _hovering ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: IconButton(
                  tooltip: 'Edit & resend',
                  iconSize: 15,
                  visualDensity: touchSafeDensity,
                  color: colors.textSecondary,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: _edit,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 600),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceAlt,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    message.text,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

/// Full-size preview of an attached file: image inline, text decoded, PDF as a
/// download (browsers render PDFs from the saved file). Bytes load from the
/// in-session copy or the IndexedDB asset store.
