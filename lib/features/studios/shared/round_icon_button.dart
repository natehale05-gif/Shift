


/// Renders a mock studio result inline in the chat. Every visual/audio/video
/// artifact here is procedurally generated at render time — nothing is a
/// real diffusion/video model output. Audio is a real (synthesized) WAV file
/// so playback and download both work; images/video download a real PNG
/// snapshot of the rendered art/thumbnail.
library;
import 'package:flutter/material.dart';

class RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool loading;
  final String? tooltip;

  const RoundIconButton({super.key, 
    required this.icon,
    required this.onPressed,
    this.loading = false,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final button = Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              icon: Icon(icon, color: Colors.white),
              onPressed: onPressed,
            ),
    );
    return tooltip != null ? Tooltip(message: tooltip!, child: button) : button;
  }
}
