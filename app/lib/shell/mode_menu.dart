import 'package:flutter/material.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
import 'mode.dart';

/// The mode switcher, as an iOS pull-down menu.
///
/// The shape is the platform's, not an invention: a title that is also a
/// button, a chevron that says so, and a rounded panel of rows underneath.
/// Details that make it read as native rather than as a menu someone drew:
///
/// * **Rows are 44pt** and the label is **17pt** — body size. A 14pt row is
///   the most common tell that a menu was styled on a desktop.
/// * **The icon is on the trailing edge.** Apple puts it there; Material puts
///   it on the leading edge, and following Material here is what made the
///   first version look like an Android app in Apple colours.
/// * **A checkmark marks the current row**, rather than a filled background.
///   Selection in an iOS menu is stated, not highlighted.
/// * **Hairline separators**, inset to the text, between rows.
/// * **No stroke around the panel.** iOS menus have a shadow and no border.
///
/// Subtitles are a real iOS menu element (Files and Photos both use them), so
/// the line saying what each mode is for survives the move — it is the part
/// that answers "why would I go there", which "Work" alone does not.
class ModeMenu extends StatelessWidget {
  final AppMode current;
  final ValueChanged<AppMode> onSelect;

  const ModeMenu({super.key, required this.current, required this.onSelect});

  /// Apple's pull-down width. Wide enough for a two-line subtitle, and still
  /// inside a 320pt phone once the screen's own margins are allowed for.
  static const double panelWidth = 280;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return MenuAnchor(
      alignmentOffset: const Offset(0, Space.xs),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surfaceRaised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(8),
        shadowColor: WidgetStatePropertyAll(c.text.withValues(alpha: 0.18)),
        shape: WidgetStatePropertyAll(
          // 13, which is iOS's menu radius. Not 12 and not 16 — at this size
          // the difference is visible next to a real system menu.
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
      ),
      menuChildren: [
        for (final (i, mode) in AppMode.values.indexed) ...[
          if (i > 0)
            // Inset to the text, which is how every grouped list and menu on
            // the platform draws its separators. A full-bleed rule reads as a
            // table.
            Padding(
              padding: const EdgeInsets.only(left: Space.lg),
              child: Divider(height: 0.5, thickness: 0.5, color: c.divider),
            ),
          _ModeItem(
            mode: mode,
            selected: mode == current,
            onSelect: onSelect,
          ),
        ],
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
                  // Title 3 semibold: a nav-bar title that happens to be a
                  // button. The mode is the most important word on screen.
                  style: text.headlineSmall?.copyWith(color: c.text),
                ),
                const SizedBox(width: Space.xs),
                // A small plain chevron, not a filled disc.
                //
                // The first attempt used `expand_circle_down_rounded`, which
                // on the reasoning that iOS pull-downs use a circled chevron
                // sounded right and rendered as a heavy dark dot beside the
                // title — Material's disc is solid where Apple's is a hairline
                // ring. A bare 15pt chevron in tertiary grey is both closer to
                // the platform and quieter, which is the point of it.
                Icon(Icons.keyboard_arrow_down_rounded,
                    size: 22, color: c.textFaint),
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
          EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
        ),
        backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      child: SizedBox(
        width: ModeMenu.panelWidth - Space.lg * 2,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mode.label,
                    // Body, 17. Semibold only when current, which with the
                    // checkmark is the whole of the selected treatment — an
                    // iOS menu does not tint its rows.
                    style: text.bodyLarge?.copyWith(
                      color: c.text,
                      fontWeight:
                          selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    mode.menuHint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: c.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.md),
            // Trailing, which is the side Apple uses. A checkmark replaces the
            // mode's own icon on the current row, because the row's job then
            // is to say "you are here" rather than to identify itself.
            Icon(
              selected ? Icons.check_rounded : mode.icon,
              size: 20,
              color: selected ? c.accent : c.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}
