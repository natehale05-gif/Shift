


/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.
import '../../../core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

class StudioBadge extends StatelessWidget {
  final String text;
  const StudioBadge({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}
