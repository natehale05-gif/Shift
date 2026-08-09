import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/design/palette.dart';
import '../core/device/device_class.dart';
import 'mode.dart';
import 'mode_pills.dart';
import 'mode_placeholder.dart';
import 'mode_rail.dart';
import 'shell_controller.dart';

/// The frame every mode lives inside.
///
/// Two arrangements, chosen by device class rather than by window width — see
/// [deviceClassOf] for why those are different questions. A rail on anything
/// roomy (desktop and tablet, including an iPad), a row of pills on a phone.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = context.watch<ShellController>();

    // The window, in logical pixels.
    //
    // This started out reading `View.of(context).display.size` — the physical
    // screen — on the reasoning that an iPad in Split View is still an iPad.
    // Two things killed that, both found by measuring rather than reasoning:
    //
    // 1. `Display.size` documents itself as physical pixels, and on web it
    //    returns logical ones. Dividing by the device pixel ratio, as the
    //    documented contract requires, turned a 390pt phone into 130 — and
    //    130 is a phone either way, so the bug was invisible until a wider
    //    device landed on the wrong side of the boundary.
    // 2. A third of an iPad genuinely cannot host a file tree, an editor and
    //    a terminal. Demoting it to the phone surface is the better answer,
    //    not a compromise.
    //
    // The invariant that actually mattered — a desktop window dragged narrow
    // must not swap someone's IDE for a task list — is not carried by this
    // number at all. It is carried by [deviceClassOf]'s platform arm, which
    // answers `desktop` for a desktop OS at any size.
    final deviceClass = deviceClassOf(
      platform: Theme.of(context).platform,
      shortestSide: MediaQuery.sizeOf(context).shortestSide,
      override: shell.deviceOverride,
    );

    final body = _ModeBody(mode: shell.mode);

    return Scaffold(
      backgroundColor: context.colors.ground,
      body: deviceClass.isRoomy
          ? Row(
              children: [
                ModeRail(current: shell.mode, onSelect: shell.openMode),
                Expanded(child: body),
              ],
            )
          : Column(
              children: [
                ModePills(current: shell.mode, onSelect: shell.openMode),
                Expanded(child: body),
              ],
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
