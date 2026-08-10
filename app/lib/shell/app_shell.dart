import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
import 'mode.dart';
import 'mode_menu.dart';
import 'mode_placeholder.dart';
import 'shell_controller.dart';

/// The frame every mode lives inside.
///
/// **One switcher on every device.** This was a rail on desktop and a
/// scrolling row of pills on a phone, chosen by device class. Both are gone in
/// favour of a single dropdown, which is simpler to hold in your head and, on
/// the phone, fixes the thing the pills spent most of their code apologising
/// for: six labelled destinations do not fit across a phone, so two of six
/// were always off-screen behind a scroll.
///
/// The device class still decides plenty — which surface Code mode gets, most
/// of all — so [deviceClassOf] and the override behind it stay. It just no
/// longer decides how you change mode.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();

    final c = context.colors;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        child: Column(
          children: [
            // A nav bar at the platform's own proportions: 44pt tall, a
            // half-pixel hairline underneath rather than a 1pt rule, and the
            // title on the leading edge. The hairline is the detail people
            // read without noticing — a full pixel reads as a web page.
            Container(
              // 44 of content *plus* the hairline. Written as 44.5 because a
              // flat 44 puts the border inside the box and leaves the tap
              // target at 43.5 — which the tap-target test caught, for the
              // third time in this shell's short life.
              height: 44.5,
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: c.divider, width: 0.5),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              child: Row(
                children: [
                  ModeMenu(current: shell.mode, onSelect: shell.openMode),
                ],
              ),
            ),
            Expanded(child: _ModeBody(mode: shell.mode)),
          ],
        ),
      ),
    );
  }
}

class _ModeBody extends StatelessWidget {
  final AppMode mode;

  const _ModeBody({required this.mode});

  @override
  Widget build(BuildContext context) {
    // An exhaustive switch, so adding a seventh mode is a decision here rather
    // than something a default answers on somebody's behalf.
    return switch (mode) {
      AppMode.chat => const ModePlaceholder(mode: AppMode.chat, wave: 'N2'),
      AppMode.code => const ModePlaceholder(mode: AppMode.code, wave: 'N9'),
      AppMode.visual => const ModePlaceholder(mode: AppMode.visual, wave: 'N4'),
      AppMode.design => const ModePlaceholder(mode: AppMode.design, wave: 'N5'),
      AppMode.work => const ModePlaceholder(mode: AppMode.work, wave: 'N10'),
      AppMode.notes => const ModePlaceholder(mode: AppMode.notes, wave: 'N3'),
    };
  }
}
