


import 'package:flutter/material.dart';
import '../../../core/theme/tap_targets.dart';


/// Claude-style composer: a single rounded card holding the text field with
/// a row of controls beneath it — an attach button, a model chip, and a
/// circular purple send button.
class StopButton extends StatelessWidget {
  final VoidCallback onPressed;

  const StopButton({super.key, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Same 34pt circle in a 44pt button as SendButton — they swap places in
    // the composer, so a difference in hit area between them would move the
    // target under the thumb mid-turn.
    return SizedBox(
      width: kMinTouchTarget,
      height: kMinTouchTarget,
      child: IconButton(
        tooltip: 'Stop generating',
        padding: EdgeInsets.zero,
        icon: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.stop_rounded,
              size: 18, color: theme.colorScheme.onPrimary),
        ),
        onPressed: onPressed,
      ),
    );
  }
}
