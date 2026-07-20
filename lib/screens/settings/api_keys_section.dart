import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/api_keys_store.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_theme.dart';

/// BYOK key management. Adding an Anthropic key flips chat from Simulated
/// to Live; removing it falls straight back to the mock.
class ApiKeysSection extends StatefulWidget {
  const ApiKeysSection({super.key});

  @override
  State<ApiKeysSection> createState() => _ApiKeysSectionState();
}

class _ApiKeysSectionState extends State<ApiKeysSection> {
  late final TextEditingController _anthropicController;
  late final TextEditingController _geminiController;
  bool _showAnthropic = false;
  bool _showGemini = false;

  @override
  void initState() {
    super.initState();
    final keys = context.read<ApiKeysStore>();
    _anthropicController = TextEditingController(text: keys.anthropicKey);
    _geminiController = TextEditingController(text: keys.geminiKey);
  }

  @override
  void dispose() {
    _anthropicController.dispose();
    _geminiController.dispose();
    super.dispose();
  }

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

        // --- Anthropic ---
        Row(
          children: [
            Text('Anthropic (Claude)', style: theme.textTheme.titleSmall),
            const SizedBox(width: AppSpacing.sm),
            _StatusBadge(status: keys.anthropicStatus),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Powers live chat, coding, writing, and routing. Create a key at '
          'console.anthropic.com (API keys) — new accounts may need a small '
          'credit purchase first.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _anthropicController,
                obscureText: !_showAnthropic,
                decoration: InputDecoration(
                  hintText: 'sk-ant-…',
                  suffixIcon: IconButton(
                    icon: Icon(_showAnthropic
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _showAnthropic = !_showAnthropic),
                  ),
                ),
                onChanged: keys.setAnthropicKey,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton.tonal(
              onPressed: keys.anthropicKey.isEmpty ||
                      keys.anthropicStatus == KeyStatus.testing
                  ? null
                  : keys.testAnthropicKey,
              child: keys.anthropicStatus == KeyStatus.testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    )
                  : const Text('Test key'),
            ),
          ],
        ),
        if (keys.anthropicError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              keys.anthropicError!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: AppSpacing.lg),

        // --- Google ---
        Row(
          children: [
            Text('Google (Gemini)', style: theme.textTheme.titleSmall),
            const SizedBox(width: AppSpacing.sm),
            _StatusBadge(status: keys.geminiStatus),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Powers live image generation, Gemini chat, and Google-grounded '
          'search. Free-tier keys are available at aistudio.google.com — '
          'no purchase required.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _geminiController,
                obscureText: !_showGemini,
                decoration: InputDecoration(
                  hintText: 'AIza…',
                  suffixIcon: IconButton(
                    icon: Icon(_showGemini
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined),
                    onPressed: () =>
                        setState(() => _showGemini = !_showGemini),
                  ),
                ),
                onChanged: keys.setGeminiKey,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton.tonal(
              onPressed: keys.geminiKey.isEmpty ||
                      keys.geminiStatus == KeyStatus.testing
                  ? null
                  : keys.testGeminiKey,
              child: keys.geminiStatus == KeyStatus.testing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.6),
                    )
                  : const Text('Test key'),
            ),
          ],
        ),
        if (keys.geminiError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              keys.geminiError!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: colors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          ),
          child: Text(
            keys.isLive
                ? 'Live mode is on — chat now calls the real API with your '
                    'key. Clear the key to return to simulated demos.'
                : 'No keys yet — everything runs in simulated demo mode, '
                    'free and offline-friendly.',
            style: theme.textTheme.bodySmall,
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
