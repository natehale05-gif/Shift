import 'package:flutter/material.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
import 'mode.dart';

/// The mode switcher, shaped like Claude's model picker.
///
/// A quiet text button with the current name and a small chevron, opening a
/// soft-cornered panel of rows. The differences from the iOS pull-down this
/// replaced are all deliberate, and together they are most of why one reads as
/// Claude and the other as a system menu:
///
/// * **A bordered panel, not a shadowed one.** Claude's surfaces are defined
///   by a hairline and a large radius; iOS defines them by a shadow and no
///   border. This is the single most visible difference.
/// * **12pt radius**, not 13 — and the rows are inset, so the highlight on a
///   hovered row is a rounded rectangle inside the panel rather than a
///   full-bleed band.
/// * **Rows are 15pt**, not body-sized. Claude's interface is denser than a
///   phone-first one.
/// * **The current row is washed in the accent** and keeps a check. iOS states
///   selection without tinting; Claude tints.
/// * **No separators.** Spacing carries the grouping.
class ModeMenu extends StatelessWidget {
  final AppMode current;
  final ValueChanged<AppMode> onSelect;

  const ModeMenu({super.key, required this.current, required this.onSelect});

  /// Wide enough for the hint line, and still inside a 320pt phone once the
  /// screen's own margins are allowed for.
  static const double panelWidth = 272;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return MenuAnchor(
      alignmentOffset: const Offset(0, Space.xs),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surfaceRaised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        // Barely-there elevation: the hairline does the work, and a heavy
        // shadow under a bordered panel reads as two competing edges.
        elevation: const WidgetStatePropertyAll(3),
        shadowColor: WidgetStatePropertyAll(c.text.withValues(alpha: 0.10)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: c.border),
          ),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(Space.xs)),
      ),
      menuChildren: [
        for (final mode in AppMode.values)
          _ModeItem(
            mode: mode,
            selected: mode == current,
            onSelect: onSelect,
          ),
      ],
      builder: (context, controller, _) => Semantics(
        button: true,
        label: 'Mode: ${current.label}',
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Container(
            constraints: const BoxConstraints(minHeight: kMinTouchTarget),
            padding: const EdgeInsets.symmetric(
              horizontal: Space.sm,
              vertical: Space.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  current.label,
                  // A label, not a title. Claude's model picker is a quiet
                  // control in the corner, not the loudest word on screen.
                  style: text.titleMedium?.copyWith(color: c.textMuted),
                ),
                const SizedBox(width: Space.xxs),
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: c.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeItem extends StatelessWidget {
  final AppMode mode;
  final bool selected;
  final ValueChanged<AppMode> onSelect;

  const _ModeItem({
    required this.mode,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return MenuItemButton(
      onPressed: () => onSelect(mode),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(
          Size(ModeMenu.panelWidth, kMinTouchTarget),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: Space.md, vertical: 10),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
        ),
        // Tinted rather than merely checked, which is Claude's way of showing
        // a current item.
        backgroundColor: WidgetStatePropertyAll(
          selected ? c.accentWash : Colors.transparent,
        ),
      ),
      child: SizedBox(
        width: ModeMenu.panelWidth - Space.md * 2 - Space.xs * 2,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mode.label,
                    style: text.bodyMedium?.copyWith(
                      color: selected ? c.accent : c.text,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: Space.xxs),
                  Text(
                    mode.menuHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: c.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            // Only the current row carries a mark, and the others carry
            // nothing — Claude's menus are not icon lists.
            if (selected)
              Icon(Icons.check_rounded, size: 16, color: c.accent),
          ],
        ),
      ),
    );
  }
}
