
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/stores/conversation_store.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
class ContinueButton extends StatelessWidget {
  final String messageId;

  const ContinueButton({super.key, required this.messageId});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () =>
          context.read<ConversationStore>().continueReply(messageId),
      icon: const Icon(Icons.play_arrow_rounded, size: 16),
      label: const Text('Continue'),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

/// Regenerate control: a plain tap re-runs with Auto; the menu also offers
/// "Retry with …" for each chat model the user has a key for.
