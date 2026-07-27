


import 'package:flutter/material.dart';


/// Claude-style composer: a single rounded card holding the text field with
/// a row of controls beneath it — an attach button, a model chip, and a
/// circular purple send button.
class SendButton extends StatelessWidget {
  final bool enabled;
  final VoidCallback onPressed;

  const SendButton({super.key, required this.enabled, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedOpacity(
      opacity: enabled ? 1 : 0.4,
      duration: const Duration(milliseconds: 120),
      child: SizedBox(
        width: 34,
        height: 34,
        child: IconButton.filled(
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.primary,
            foregroundColor: theme.colorScheme.onPrimary,
          ),
          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
