import 'package:flutter/material.dart';

import '../design/metrics.dart';
import '../design/palette.dart';

/// The pill that floats over every screen of an agent mode.
///
/// **Permanent, and that is the point.** In the reference it is present on the
/// lists as well as inside an agent, so starting work never means navigating
/// somewhere first — you type where you are. Content scrolls under it rather
/// than being pushed above it.
///
/// Shared by Code and Work, and it takes its colours from [context.colors]
/// rather than naming any — which is what lets one widget be dark chrome in
/// one mode and paper in the other without knowing about either.
///
/// Only the placeholder changes: "Plan, ask, build…" out in the lists, "Follow
/// up…" inside an agent that is already running.
class AgentComposer extends StatefulWidget {
  final String hint;

  /// Null while there is nothing to send to — an agent that is already working.
  /// The field goes read-only rather than disappearing, because a composer that
  /// comes and goes makes the screen jump under a thumb that is already there.
  final ValueChanged<String>? onSend;

  const AgentComposer({
    super.key,
    required this.onSend,
    this.hint = 'Plan, ask, build…',
  });

  /// What a scrolling list must leave clear beneath it. Exported so the lists
  /// pad themselves rather than each guessing.
  static const double reservedHeight = 96;

  @override
  State<AgentComposer> createState() => _AgentComposerState();
}

class _AgentComposerState extends State<AgentComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final send = widget.onSend;
    final text = _controller.text.trim();
    if (send == null || text.isEmpty) return;
    _controller.clear();
    send(text);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.md),
      child: Container(
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: Space.xs),
        child: Row(
          children: [
            _Round(
              icon: Icons.add_rounded,
              tooltip: 'Attach',
              onTap: null,
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                readOnly: widget.onSend == null,
                style: text.bodyLarge?.copyWith(color: c.text),
                cursorColor: c.accent,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  isDense: true,
                  filled: false,
                  fillColor: Colors.transparent,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: widget.hint,
                  hintStyle: text.bodyLarge?.copyWith(color: c.textFaint),
                ),
              ),
            ),
            _Round(
              icon: Icons.mic_none_rounded,
              tooltip: 'Dictate — not built yet',
              onTap: null,
            ),
          ],
        ),
      ),
    );
  }
}

class _Round extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _Round({required this.icon, required this.tooltip, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: kMinTouchTarget,
        height: kMinTouchTarget,
        child: Center(
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: c.surface,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: onTap,
              icon: Icon(icon, size: 18),
              color: c.textMuted,
              disabledColor: c.textFaint,
            ),
          ),
        ),
      ),
    );
  }
}
