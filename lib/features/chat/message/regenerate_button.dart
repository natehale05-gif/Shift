
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/chat_message.dart';
import '../../../turn/chat_service.dart';
import '../../../providers/clients/provider_capability.dart';
import '../../../data/stores/api_keys_store.dart';
import '../../../data/stores/conversation_store.dart';
import '../../../core/theme/app_theme.dart';

/// Claude-style message layout: user turns are compact right-aligned bubbles;
/// assistant turns are open prose — an ordered sequence of thinking, tool,
/// text, image, and artifact blocks — with a hover action row underneath.
class RegenerateButton extends StatelessWidget {
  final ChatMessage message;

  const RegenerateButton({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final keys = context.watch<ApiKeysStore>();
    final registry = keys.registry;
    final keyedProviders = [
      for (final d in registry.all)
        if (keys.hasKey(d.id) &&
            d.modelsFor(ProviderCapability.chat).isNotEmpty)
          d,
    ];

    void regen(String? pin) => context.read<ConversationStore>().regenerate(
          message.id,
          options: pin == null ? ChatOptions.none : ChatOptions(modelPin: pin),
        );

    return PopupMenuButton<String>(
      tooltip: 'Regenerate',
      position: PopupMenuPosition.under,
      onSelected: (value) => regen(value == 'auto' ? null : value),
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'auto', child: Text('Try again')),
        for (final provider in keyedProviders) ...[
          PopupMenuItem(
            enabled: false,
            height: 32,
            child: Text(
              provider.displayName.toUpperCase(),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: colors.textSecondary, letterSpacing: 0.5),
            ),
          ),
          for (final model in provider.modelsFor(ProviderCapability.chat))
            PopupMenuItem(
              value: model.id,
              child: Text('Retry with ${model.displayName}'),
            ),
        ],
      ],
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(Icons.refresh_rounded, size: 15, color: colors.textSecondary),
      ),
    );
  }
}

/// The ‹ 1/2 › switcher shown under a reply that has been regenerated, so the
/// user can step between the alternative responses.
