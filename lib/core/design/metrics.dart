/// Spacing, radii, motion and touch minimums.
///
/// A scale rather than a grab-bag: sizes come from this list or they are wrong.
/// Arbitrary padding is how a layout ends up almost-aligned everywhere, which
/// looks like carelessness even when nobody can point at the offending number.
class Space {
  const Space._();

  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;

  /// The outer gutter of a screen, which changes with how much room there is.
  static const gutterCompact = 16.0;
  static const gutterRegular = 24.0;
  static const gutterWide = 32.0;
}

class Radii {
  const Radii._();

  static const xs = 6.0;
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 20.0;
  static const xl = 28.0;

  /// For anything that should read as a lozenge regardless of its height.
  static const pill = 999.0;
}

class Motion {
  const Motion._();

  /// A state flip the user already knows about — a toggle, a hover.
  static const instant = Duration(milliseconds: 90);

  /// The default: a panel opening, a chip appearing.
  static const quick = Duration(milliseconds: 180);

  /// Something moving a real distance across the screen.
  static const settled = Duration(milliseconds: 280);

  /// Reserved for a full surface transition, and used sparingly. Motion that
  /// outlasts a thought stops reading as responsiveness and starts reading as
  /// lag, which is the opposite of what it was added for.
  static const deliberate = Duration(milliseconds: 420);
}

/// The smallest a tappable thing may be.
///
/// 44 is Apple's minimum and the stricter of the two platform guidelines, so
/// it is the one used everywhere rather than branching per platform — a
/// control that is comfortable on iOS is comfortable on Android, and the
/// reverse is not true.
///
/// This is asserted by a widget test rather than trusted, because it is
/// exactly the kind of rule that holds for a month and then quietly stops.
const double kMinTouchTarget = 44.0;

/// Breakpoints, measured against the window.
///
/// Layout-only. **Do not use these to decide device class** — a desktop window
/// dragged narrow is not a phone, and Code mode in particular must not swap an
/// IDE for a task list because someone resized a window. Device class lives in
/// `core/device/device_class.dart` and answers a different question.
class Breaks {
  const Breaks._();

  /// Below this: one column, nothing beside it.
  static const compact = 700.0;

  /// Below this: two columns at most.
  static const regular = 1100.0;
}
