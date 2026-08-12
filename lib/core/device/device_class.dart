import 'package:flutter/foundation.dart';

/// What kind of machine this is.
///
/// Deliberately **not** derived from the window. The two questions look alike
/// and are not: how much room is there right now (a layout question, answered
/// by `Breaks`) versus what is this thing (a product question, answered here).
///
/// Code mode is why the distinction has to be real. It shows an IDE on a
/// desktop or a tablet and a task list on a phone — two different surfaces,
/// not one responsive layout — so if the answer came from window width, then
/// dragging a desktop window narrow would replace someone's editor with a task
/// list mid-edit. That is not a layout adapting; that is the app changing out
/// from under them.
enum DeviceClass {
  /// A handset. Thumb-driven, one thing on screen at a time.
  phone,

  /// A tablet, including an iPad with or without a keyboard. Gets the full
  /// desktop surfaces — the request was explicit that an iPad is a desktop
  /// experience, and the screen supports it.
  tablet,

  /// A real computer.
  desktop;

  /// Whether this class gets the multi-pane, keyboard-first surfaces.
  bool get isRoomy => this != DeviceClass.phone;
}

/// The line between a phone and a tablet, in logical pixels of the *physical
/// display's* shortest side.
///
/// 600 is the long-standing Android breakpoint for "large screen", and it puts
/// every current iPad (smallest shortest-side is 744) firmly on the tablet
/// side while leaving the largest phones (around 430) well clear. A number
/// chosen to sit in a gap rather than near a real device is one that will not
/// need revisiting when a phone gets slightly bigger.
const double kTabletShortestSide = 600.0;

/// Decides the device class.
///
/// Pure, and takes its inputs explicitly so it can be tested without a
/// binding, a window, or a real device.
///
/// [shortestSide] is the shortest side of the **window**, in logical pixels.
///
/// Deliberately the window and not the screen, and the reasoning changed
/// during N0 after measuring: `Display.size` documents itself as physical
/// pixels and returns logical ones on web, so the "correct" conversion was
/// silently wrong; and a third of an iPad in Split View genuinely cannot host
/// a file tree, an editor and a terminal, so the phone surface is the better
/// answer there rather than a demotion.
///
/// This value carries **no** responsibility for the invariant that matters —
/// a desktop window dragged narrow must keep the IDE. That is the platform
/// switch below, which answers [DeviceClass.desktop] at any size.
///
/// **On the web, [platform] comes from the browser, and it can be wrong.**
/// An iPhone with "Request Desktop Website" on reports macOS; a browser under
/// automation reports its host OS whatever user agent it is given. Both land
/// on [DeviceClass.desktop], which is why [override] is not a nicety.
///
/// [override] wins over everything. Somebody will disagree with the automatic
/// answer — a small tablet used one-handed, a large phone used with a case
/// stand — and they are entitled to; a rule with no escape hatch is a rule
/// that will be wrong for someone permanently.
DeviceClass deviceClassOf({
  required TargetPlatform platform,
  required double shortestSide,
  DeviceClass? override,
}) {
  if (override != null) return override;

  switch (platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
      return shortestSide >= kTabletShortestSide
          ? DeviceClass.tablet
          : DeviceClass.phone;

    // A desktop OS is a desktop however small the window is. This is the arm
    // that stops a narrowed browser from being mistaken for a handset.
    case TargetPlatform.macOS:
    case TargetPlatform.windows:
    case TargetPlatform.linux:
      return DeviceClass.desktop;
  }
}
