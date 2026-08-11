import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';
import '../../core/design/typography.dart';
import '../../shell/mode.dart';
import '../artifacts/artifact_panel.dart';
import '../chat/composer.dart';
import '../chat/failure_card.dart';
import '../chat/turn_controller.dart';
import 'design_turns.dart';

/// Design mode: the thing being made *is* the screen.
///
/// The difference from Chat is one decision and it is the whole mode. In Chat
/// a page is a deliverable beside the conversation, in a panel you can close.
/// Here there is no conversation on screen at all — the design fills it, and
/// the composer under it is for arguing with what you can see.
///
/// So this reuses [ArtifactPanel] rather than reinventing a canvas: preview,
/// code, versions, copy and save are the same things a design needs, and a
/// second implementation of them would drift.
class DesignSurface extends StatelessWidget {
  const DesignSurface({super.key});

  @override
  Widget build(BuildContext context) {
    final turn = context.watch<DesignTurns>();
    final design = turn.openArtifact ??
        (turn.produced.isEmpty ? null : turn.produced.last);

    return Column(
      children: [
        Expanded(
          child: design == null
              ? _NothingYet(busy: turn.running)
              : ArtifactPanel(artifact: design),
        ),
        // The failure lives on a reply nothing here draws, so without this a
        // design that never arrives looks like a button that did nothing.
        if (turn.items.whereType<Reply>().lastOrNull
            case final Reply reply when reply.failure != null && !turn.running)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: FailureCard(reply: reply),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
              Space.lg, Space.sm, Space.lg, Space.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Composer(
                // The hint changes because the job does: the first message
                // describes a thing, every one after it changes the thing on
                // screen.
                hint: design == null
                    ? 'Describe what you want made'
                    : 'Say what to change',
                busy: turn.running,
                onStop: turn.stop,
                onSend: (text) => turn.send(text, mode: AppMode.design),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NothingYet extends StatelessWidget {
  final bool busy;

  const _NothingYet({required this.busy});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(AppMode.design.activeIcon, size: 30, color: c.accent),
            const SizedBox(height: Space.lg),
            Text(
              busy
                  ? 'Designing…'
                  : 'A page, a poster, a deck, an invitation.\n'
                      'Say what it is for and who it is for.',
              textAlign: TextAlign.center,
              style: ShiftType.proseStyle(c.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
