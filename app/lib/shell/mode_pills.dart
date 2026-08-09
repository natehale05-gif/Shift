import 'package:flutter/material.dart';

import '../core/design/metrics.dart';
import '../core/design/palette.dart';
import '../core/design/typography.dart';
import 'mode.dart';

/// The mode switcher on a phone: a scrolling row of pills across the top.
///
/// **Not a bottom navigation bar**, and that is a decision rather than a
/// preference. Two of the six modes — Chat and Notes — own the bottom of the
/// screen for their composer, which is where a thumb rests and where the
/// keyboard pushes everything anyway. A bottom bar would spend the app's most
/// valuable real estate on navigation the user touches once a session, and
/// then fight the composer for it every time the keyboard opens.
///
/// The top row also sidesteps the count problem: platform tab bars start
/// collapsing into "More" at five, and there are six modes, none of which is
/// the one to hide.
///
/// Six labelled pills do not fit across a phone, so the row scrolls — which
/// creates the problem this widget spends most of its code on. Two of six
/// top-level destinations being off-screen with no hint is how a feature goes
/// unfound, so the right edge fades to signal there is more, and the selected
/// pill is always scrolled into view.
class ModePills extends StatefulWidget {
  final AppMode current;
  final ValueChanged<AppMode> onSelect;

  const ModePills({super.key, required this.current, required this.onSelect});

  @override
  State<ModePills> createState() => _ModePillsState();
}

class _ModePillsState extends State<ModePills> {
  final _controller = ScrollController();
  final _keys = {for (final m in AppMode.values) m: GlobalKey()};

  @override
  void didUpdateWidget(ModePills old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) _revealCurrent();
  }

  @override
  void initState() {
    super.initState();
    // The mode can be set from outside the row entirely — a Shortcut, Siri, a
    // deep link — and landing on a screen whose active tab is scrolled out of
    // sight reads as the app having ignored you.
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
  }

  void _revealCurrent() {
    final context = _keys[widget.current]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: Motion.quick,
      curve: Curves.easeOut,
      alignment: 0.5,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.ground,
        border: Border(bottom: BorderSide(color: c.divider)),
      ),
      child: SafeArea(
        bottom: false,
        // 64 less 2x8 of padding leaves 48pt pills, comfortably over the
        // minimum. The first draft was 56, which left them at 40 — caught by
        // the tap-target test rather than by looking at it, which is the
        // entire reason that test measures instead of trusting.
        child: SizedBox(
          height: 64,
          child: Stack(
            children: [
              // A Row inside a scroll view, not a ListView. A ListView builds
              // its children lazily, so a pill that is off the right edge is
              // not in the tree at all — its GlobalKey has no context, and
              // `ensureVisible` silently does nothing. That is precisely the
              // case the scrolling exists for, so the lazy version fails only
              // when it matters. Six fixed items do not need virtualising.
              SingleChildScrollView(
                controller: _controller,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm,
                ),
                child: Row(
                  // Without this the Row sizes each pill to its intrinsic
                  // height — 22pt — where the ListView it replaced stretched
                  // them to the cross-axis extent. Same tap-target test caught
                  // it a second time, for a different reason.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final mode in AppMode.values)
                      _Pill(
                        key: _keys[mode],
                        mode: mode,
                        selected: mode == widget.current,
                        onTap: () => widget.onSelect(mode),
                      ),
                  ],
                ),
              ),
              // The "there is more this way" hint. Ignores pointers so it
              // never eats a tap meant for the pill underneath it.
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: IgnorePointer(
                  child: Container(
                    width: Space.xxl,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [c.ground.withValues(alpha: 0), c.ground],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final AppMode mode;
  final bool selected;
  final VoidCallback onTap;

  const _Pill({
    super.key,
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
      child: Padding(
        padding: const EdgeInsets.only(right: Space.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(Radii.pill),
          child: AnimatedContainer(
            duration: Motion.instant,
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            // Height comes from the row; the tap target is widened to the
            // minimum instead, because a pill that is tall enough but 30px
            // wide is still a pill you miss.
            constraints: const BoxConstraints(minWidth: kMinTouchTarget),
            decoration: BoxDecoration(
              color: selected ? c.accentWash : c.surface,
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: selected ? c.accent : c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? mode.activeIcon : mode.icon,
                  size: 16,
                  color: selected ? c.accent : c.textMuted,
                ),
                const SizedBox(width: Space.xs + 2),
                Text(
                  mode.label,
                  style: TextStyle(
                    fontFamily: ShiftType.ui,
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? c.accent : c.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
