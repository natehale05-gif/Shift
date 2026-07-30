


import 'package:flutter/material.dart';
import '../../../core/theme/tap_targets.dart';


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
      // The circle stays 34; the button around it is 44, which is Apple's
      // minimum. It used to be clamped to 34 both ways — ten points short on
      // the single most-tapped control in the app, so a thumb aimed at the
      // middle of it could still miss.
      child: SizedBox(
        width: kMinTouchTarget,
        height: kMinTouchTarget,
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.arrow_upward_rounded,
                size: 18, color: theme.colorScheme.onPrimary),
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}
