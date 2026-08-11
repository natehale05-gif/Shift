import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';

/// Says a chat is private, and says exactly what that means.
///
/// **Both halves are the feature.** A private mode nobody can see is a private
/// mode nobody trusts, so it is stated on the screen the whole time rather than
/// implied by a menu item chosen a minute ago.
///
/// And the second line is not a disclaimer bolted on: this app keeps nothing,
/// but the words still go to whichever provider answers them, under that
/// provider's terms. Saying only "Private" would be a promise the app cannot
/// keep on behalf of someone else — the kind of privacy claim that is worse
/// than making none.
class PrivateBanner extends StatelessWidget {
  const PrivateBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: Space.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: Space.md, vertical: Space.sm),
      decoration: BoxDecoration(
        color: c.surfaceSunken,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.visibility_off_outlined, size: 16, color: c.textMuted),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                  text: 'Private chat. ',
                  style: text.bodySmall?.copyWith(
                      color: c.text, fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: 'Nothing here is saved — leaving loses it. The '
                      'messages still go to the provider that answers them.',
                  style: text.bodySmall?.copyWith(color: c.textMuted),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
