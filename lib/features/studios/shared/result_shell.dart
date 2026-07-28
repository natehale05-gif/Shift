


/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class ResultShell extends StatelessWidget {
  final Widget child;
  final Widget? footer;
  final double maxWidth;

  const ResultShell({super.key, required this.child, this.footer, this.maxWidth = 320});

  @override
  Widget build(BuildContext context) {
    final border = Theme.of(context).extension<AppSemanticColors>()!.border;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            child,
            if (footer != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}
