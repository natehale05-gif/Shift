import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/providers/provider_descriptor.dart';
import '../../state/api_keys_store.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

/// BYOK key management. Adding any provider key flips chat from Simulated to
/// Live; removing the last one falls straight back to the mock. The list of
/// providers is driven entirely off [ApiKeysStore.registry], so new providers
/// appear here automatically with no change to this file.
class ApiKeysSection extends StatelessWidget {
  const ApiKeysSection({super.key});

  @override
  Widget build(BuildContext context) {
    final keys = context.watch<ApiKeysStore>();
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bring your own keys to switch from simulated demos to live AI. '
          'Keys are stored only in this browser and calls go directly from '
          'your browser to the provider — usage bills to your account, and '
          'anyone with access to this browser profile could read the keys.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.lg),
        for (final descriptor in keys.registry.all) ...[
          _ProviderKeyRow(descriptor: descriptor),
          const SizedBox(height: AppSpacing.lg),
        ],
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Text(
            keys.isLive
                ? 'Live mode is on — chat now calls the real API with your '
                    'key. Clear every key to return to simulated demos.'
                : 'No keys yet — everything runs in simulated demo mode, '
                    'free and offline-friendly.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// One provider's key field, status badge, test button, guidance, and — for
/// CORS-risky providers — a browser caution line. Manages its own text
/// controller and show/hide toggle.
class _ProviderKeyRow extends StatefulWidget {
  final ProviderDescriptor descriptor;

  const _ProviderKeyRow({required this.descriptor});

  @override
  State<_ProviderKeyRow> createState() => _ProviderKeyRowState();
}

class _ProviderKeyRowState extends State<_ProviderKeyRow> {
  late final TextEditingController _controller;
  bool _show = false;

  @override
  void initState() {
    super.initState();
    final keys = context.read<ApiKeysStore>();
    _controller =
        TextEditingController(text: keys.keyFor(widget.descriptor.id));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final descriptor = widget.descriptor;
    final keys = context.watch<ApiKeysStore>();
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;

    final status = keys.statusFor(descriptor.id);
    final error = keys.errorFor(descriptor.id);
    final hasKey = keys.hasKey(descriptor.id);
    final hint =
        descriptor.hintPrefix.isEmpty ? 'API key' : '${descriptor.hintPrefix}…';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(descriptor.displayName, style: theme.textTheme.titleSmall),
            const SizedBox(width: AppSpacing.sm),
            _StatusBadge(status: status),
          ],
        ),
        if (descriptor.guidanceText.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(descriptor.guidanceText, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                obscureText: !_show,
                decoration: InputDecoration(
                  hintText: hint,
                  suffixIcon: IconButton(
                    icon: Icon(_show
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () => setState(() => _show = !_show),
                  ),
                ),
                onChanged: (value) => keys.setKey(descriptor.id, value),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton.tonal(
              onPressed: !hasKey || status == KeyStatus.testing
                  ? null
                  : () => keys.testKey(descriptor.id),
              child: status == KeyStatus.testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    )
                  : const Text('Test key'),
            ),
          ],
        ),
        if (descriptor.browserWarning != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: colors.textSecondary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    descriptor.browserWarning!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              error,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final KeyStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppSemanticColors>()!;
    final (label, color) = switch (status) {
      KeyStatus.none => ('not set', colors.textSecondary),
      KeyStatus.untested => ('untested', colors.textSecondary),
      KeyStatus.testing => ('testing…', colors.textSecondary),
      KeyStatus.valid => ('valid', const Color(0xFF30D158)),
      KeyStatus.invalid => ('problem', theme.colorScheme.error),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}
