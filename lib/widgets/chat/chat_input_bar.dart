import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/studio_type.dart';
import '../../state/conversation_store.dart';
import '../../theme/app_spacing.dart';
import 'studio_quick_action_chip.dart';
import 'studio_request_sheets.dart';

class ChatInputBar extends StatefulWidget {
  const ChatInputBar({super.key});

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  static const _studios = [
    StudioType.imageStudio,
    StudioType.videoStudio,
    StudioType.voiceAvatarStudio,
    StudioType.musicStudio,
    StudioType.copyScriptsStudio,
    StudioType.codeStudio,
  ];

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    context.read<ConversationStore>().sendMessage(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  Future<void> _openStudioSheet(StudioType studioType) async {
    final request = await showStudioRequestSheet(context, studioType);
    if (request == null || !mounted) return;
    context.read<ConversationStore>().sendMessage('', structuredRequest: request);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final studio in _studios) ...[
                  StudioQuickActionChip(
                    studioType: studio,
                    onTap: () => _openStudioSheet(studio),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: 'Message SHIFT AI…',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(
                onPressed: _send,
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
