import 'package:flutter/material.dart';

import '../../core/design/metrics.dart';
import '../../core/design/palette.dart';

/// Pushes a screen that keeps Code mode's surface.
///
/// A pushed route is built by the app's [Navigator], which sits **above** the
/// `Theme` the shell wraps Code mode in — so a screen pushed from here would
/// render on the app's cream paper instead. Every push in this mode goes
/// through this rather than through `MaterialPageRoute` directly, because the
/// failure is invisible until you tap something on a device.
Route<void> codeRoute(WidgetBuilder builder) => MaterialPageRoute<void>(
      builder: (context) => Theme(
        data: Theme.of(context).copyWith(extensions: const [ShiftColors.code]),
        child: Builder(builder: builder),
      ),
    );

/// The circular buttons that sit at the top of every screen in this mode.
///
/// A named widget rather than an `IconButton` with a shape, because there are
/// nine of them across the mode and the one thing they must not do is vary.
class CodeCircleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const CodeCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  /// The visible circle. The *touch* area around it is [kMinTouchTarget], which
  /// is larger — a 44pt circle drawn at 44pt leaves nothing for a thumb that
  /// lands slightly off.
  static const double diameter = 44;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: kMinTouchTarget + Space.sm,
        height: kMinTouchTarget + Space.sm,
        child: Center(
          child: Material(
            color: c.surfaceRaised,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                width: diameter,
                height: diameter,
                child: Icon(icon, size: 20, color: c.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The header on a **list** screen: a row of circles, then a large title
/// beneath it.
///
/// Deliberately not an `AppBar`. The reference puts the title on its own line
/// below the controls, at display size, and a Material app bar cannot be talked
/// into that shape without fighting it the whole way.
class CodeListHeader extends StatelessWidget {
  final String title;
  final Widget? leading;
  final List<Widget> actions;

  const CodeListHeader({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (leading != null) leading! else const SizedBox(width: Space.xs),
            const Spacer(),
            ...actions,
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.lg),
          child: Text(
            title,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: c.text, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// The header on a **detail** screen: back, a centred title, and an overflow.
///
/// A different shape from [CodeListHeader] on purpose — the reference uses the
/// standard centred nav bar once you are inside something, and the large
/// left-aligned title only at the top of a list. Two shapes, and which one you
/// are looking at tells you where you are.
class CodeDetailHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onMore;

  const CodeDetailHeader({super.key, required this.title, this.onMore});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Row(
      children: [
        CodeCircleButton(
          icon: Icons.chevron_left_rounded,
          tooltip: 'Back',
          onTap: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: c.text, fontWeight: FontWeight.w600),
          ),
        ),
        CodeCircleButton(
          icon: Icons.more_horiz_rounded,
          tooltip: 'More',
          onTap: onMore,
        ),
      ],
    );
  }
}

/// A collapsible group of rows — "Needs Attention ⌄", "Open PR ⌄".
///
/// Collapsible because a workspace with forty agents is a scroll, and the
/// header is the only place to shorten it from.
class CodeSection extends StatefulWidget {
  final String title;
  final List<Widget> children;

  const CodeSection({super.key, required this.title, required this.children});

  @override
  State<CodeSection> createState() => _CodeSectionState();
}

class _CodeSectionState extends State<CodeSection> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;
    if (widget.children.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: Space.lg),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _open = !_open),
              child: SizedBox(
                height: kMinTouchTarget,
                child: Row(
                  children: [
                    Text(widget.title,
                        style: text.bodyMedium?.copyWith(color: c.textMuted)),
                    const SizedBox(width: Space.xs),
                    Icon(
                      _open
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 18,
                      color: c.textMuted,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_open)
          for (var i = 0; i < widget.children.length; i++) ...[
            widget.children[i],
            // Inset to the text, never under the status dot — a full-bleed rule
            // here makes a list of tasks read as a table of data.
            if (i < widget.children.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: Space.lg + Space.md),
                child: Divider(height: 1, thickness: 1, color: c.divider),
              ),
          ],
      ],
    );
  }
}

/// Nothing here, and why that is fine.
class CodeEmpty extends StatelessWidget {
  final String title;
  final String detail;

  const CodeEmpty({super.key, required this.title, required this.detail});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title,
                textAlign: TextAlign.center,
                style: text.titleMedium?.copyWith(color: c.textMuted)),
            const SizedBox(height: Space.xs),
            Text(detail,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: c.textFaint)),
          ],
        ),
      ),
    );
  }
}
