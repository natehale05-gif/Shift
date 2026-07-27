


import 'package:flutter/material.dart';


/// Claude-style composer: a single rounded card holding the text field with
/// a row of controls beneath it — an attach button, a model chip, and a
/// circular purple send button.
class StopButton extends StatelessWidget {
  final VoidCallback onPressed;

  const StopButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 34,
      height: 34,
      child: IconButton.filled(
        tooltip: 'Stop generating',
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
        ),
        icon: const Icon(Icons.stop_rounded, size: 18),
        onPressed: onPressed,
      ),
    );
  }
}
