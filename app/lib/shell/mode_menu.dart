import 'package:flutter/material.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
import 'mode.dart';

/// The mode switcher: the current mode, and a menu of the other five.
///
/// One control on every device, rather than a rail on desktop and a scrolling
/// row of pills on a phone. Those were replaced deliberately and the pills'
/// central problem is the reason: six labelled destinations do not fit across
/// a phone, so the row scrolled, so two of six were always off-screen — and
/// most of that widget's code existed to soften that with a fade and an
/// auto-scroll. A menu has no such problem. Every mode is in the list, at full
/// width, with room for the sentence that says what it is for.
///
/// **Still not a bottom navigation bar**, which was the right call before and
/// still is: Chat and Notes own the bottom of the screen for their composer,
/// which is where a thumb rests and where the keyboard pushes everything
/// anyway. Platform tab bars also start collapsing into "More" at five, and
/// there are six modes, none of which is the one to hide.
class ModeMenu extends StatelessWidget {
  final AppMode current;
  final ValueChanged<AppMode> onSelect;

  const ModeMenu({super.key, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return MenuAnchor(
      // Aligned under the trigger rather than over it, so the button stays
      // visible while the menu is open — the open menu should look like it
      // belongs to the thing that opened it.
      alignmentOffset: const Offset(0, Space.xs),
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surfaceRaised),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
            side: BorderSide(color: c.border),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: Space.xs),
        ),
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
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(current.activeIcon, size: 20, color: c.accent),
                const SizedBox(width: Space.sm),
                Text(
                  current.label,
                  style: text.titleMedium?.copyWith(color: c.text),
                ),
                const SizedBox(width: Space.xs),
                Icon(Icons.expand_more_rounded, size: 20, color: c.textMuted),
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
        // The default menu item is 48 tall but only as wide as its label, and
        // its padding is symmetric. Both are set explicitly here because the
        // tap-target test has caught this exact class of thing twice already —
        // once at 40pt, once at 22pt after an unrelated layout change.
        minimumSize: const WidgetStatePropertyAll(
          Size(240, kMinTouchTarget),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
        ),
        backgroundColor: WidgetStatePropertyAll(
          selected ? c.accentWash : Colors.transparent,
        ),
      ),
      child: SizedBox(
        // Wide enough for the blurbs, narrow enough that the whole menu still
        // fits a 320pt phone once the item and menu padding are added — which
        // a test asserts, because a menu that clips its own entries is the
        // same failure as the row that scrolled them off the edge.
        width: 272,
        child: Row(
          children: [
            Icon(
              selected ? mode.activeIcon : mode.icon,
              size: 20,
              color: selected ? c.accent : c.textMuted,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    mode.label,
                    style: text.bodyMedium?.copyWith(
                      color: selected ? c.accent : c.text,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: Space.xxs),
                  // The blurb is here rather than only in the empty state
                  // because a menu is where someone decides *where to go*, and
                  // "Work" alone does not tell anyone why they would.
                  //
                  // Three lines, not two: at this width every one of the six
                  // was cut off mid-word at two, which reads as a rendering
                  // fault rather than a summary. Found by looking at it — the
                  // widget test happily asserts the text is present whether or
                  // not it is legible.
                  Text(
                    mode.blurb,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelSmall?.copyWith(
                      color: c.textFaint,
                      height: 1.35,
                    ),
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
