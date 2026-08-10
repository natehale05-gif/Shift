import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../settings/settings_screen.dart';
import 'turn_controller.dart';

/// What went wrong, stated in place.
///
/// In the interface face rather than the prose face, so it is never mistaken
/// for something a model said — a failure rendered like a reply is a failure
/// people argue with.
///
/// The disclosure is the point of this widget. One sentence can be produced by
/// four different faults (offline, blocked by the browser, refused by the
/// provider, timed out), and a screenshot of that sentence is not a diagnosis.
/// The detail is one line, collapsed, copyable — for the person diagnosing, not
/// the person reading.
class FailureCard extends StatefulWidget {
  final Reply reply;

  const FailureCard({super.key, required this.reply});

  @override
  State<FailureCard> createState() => _FailureCardState();
}

class _FailureCardState extends State<FailureCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    final reply = widget.reply;
    final detail = reply.failureDetail;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: c.textMuted),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  reply.failure ?? '',
                  style: text.bodyMedium?.copyWith(color: c.textMuted),
                ),
              ),
            ],
          ),

          // A message that names a destination should be able to get you
          // there. Without this the remedy is "open the drawer, scroll to the
          // bottom, find Settings" — three steps the sentence does not
          // mention, on a screen where the sidebar is behind a hamburger.
          // Asked about directly, which is how a discoverability problem
          // usually surfaces: as a question, not as a bug report.
          if ((reply.failure ?? '').contains('Settings')) ...[
            const SizedBox(height: Space.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SettingsScreen(),
                  ),
                ),
                icon: Icon(Icons.key_rounded, size: 16, color: c.accent),
                label: Text('Add a key',
                    style: text.labelLarge?.copyWith(color: c.accent)),
              ),
            ),
          ],

          if (detail != null) ...[
            const SizedBox(height: Space.xxs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _open = !_open),
                child: Text(
                  _open ? 'Hide details' : 'Details',
                  style: text.labelLarge?.copyWith(color: c.textFaint),
                ),
              ),
            ),
            if (_open)
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: c.surfaceSunken,
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                padding: const EdgeInsets.all(Space.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        detail,
                        style: text.bodySmall?.copyWith(
                          color: c.textMuted,
                          fontFamily: 'monospace',
                          fontFamilyFallback: const ['monospace'],
                        ),
                      ),
                    ),
                    SizedBox(
                      width: kMinTouchTarget,
                      height: kMinTouchTarget,
                      child: IconButton(
                        tooltip: 'Copy details',
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: detail)),
                        icon: const Icon(Icons.content_copy_rounded, size: 14),
                        color: c.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
