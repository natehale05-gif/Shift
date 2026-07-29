
import 'package:flutter/material.dart';

import '../../../data/models/chat_message.dart';
import '../../../data/models/message_block.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
import 'assistant_prose.dart';
import 'user_bubble.dart';

class MessageView extends StatefulWidget {
  final ChatMessage message;

  /// Invoked when the user taps an artifact card to open the artifacts panel;
  /// null renders the card non-interactive.
  final void Function(ArtifactRefBlock ref)? onOpenArtifact;

  /// Whether this is the last message in the conversation — the completed
  /// assistant reply shows follow-up suggestion chips.
  final bool isLast;

  const MessageView({
    super.key,
    required this.message,
    this.onOpenArtifact,
    this.isLast = false,
  });

  @override
  State<MessageView> createState() => _MessageViewState();
}


class _MessageViewState extends State<MessageView> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    return message.role == MessageRole.user
        ? UserBubble(message: message)
        : MouseRegion(
            onEnter: (_) => setState(() => _hovering = true),
            onExit: (_) => setState(() => _hovering = false),
            child: AssistantProse(
              message: message,
              hovering: _hovering,
              onOpenArtifact: widget.onOpenArtifact,
              isLast: widget.isLast,
            ),
          );
  }
}
