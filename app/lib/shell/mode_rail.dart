import 'package:flutter/material.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
import '../core/design/typography.dart';
import 'mode.dart';

/// The mode switcher for roomy screens: a vertical rail down the left.
///
/// Labels are always shown rather than revealed on hover. Six destinations is
/// past the count where an icon alone is unambiguous — a brush and a sparkle
/// both plausibly mean "make me a picture" — and an interface that requires
/// hovering to be read is an interface that cannot be read on a touchscreen,
/// which the iPad this rail also serves very much is.
class ModeRail extends StatelessWidget {
  final AppMode current;
  final ValueChanged<AppMode> onSelect;

  const ModeRail({super.key, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 88,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.divider)),
      ),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: Space.lg),
            const _Wordmark(),
            const SizedBox(height: Space.lg),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                children: [
                  for (final mode in AppMode.values)
                    _RailButton(
                      mode: mode,
                      selected: mode == current,
                      onTap: () => onSelect(mode),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final AppMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _RailButton({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: mode.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: AnimatedContainer(
          duration: Motion.instant,
          margin: const EdgeInsets.symmetric(
            horizontal: Space.sm,
            vertical: Space.xxs,
          ),
          padding: const EdgeInsets.symmetric(vertical: Space.sm),
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          decoration: BoxDecoration(
            color: selected ? c.accentWash : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.md),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? mode.activeIcon : mode.icon,
                size: 22,
                color: selected ? c.accent : c.textMuted,
              ),
              const SizedBox(height: Space.xs),
              Text(
                mode.label,
                style: TextStyle(
                  fontFamily: ShiftType.ui,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? c.accent : c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mark, drawn rather than shipped as an image so it stays crisp at any
/// scale and carries the brand gradient without a second asset.
class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: ShiftPalette.gradient,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      alignment: Alignment.center,
      child: const Text(
        'S',
        style: TextStyle(
          fontFamily: ShiftType.ui,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: Colors.white,
        ),
      ),
    );
  }
}
