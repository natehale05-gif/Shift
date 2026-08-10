import 'package:flutter/material.dart';

/// The type system, on Claude's scale.
///
/// ## The faces, and an honest limit
///
/// Claude's app uses **one family everywhere** — the same interface on an
/// iPhone as on a Mac. So this deliberately does *not* follow the platform:
/// an earlier version resolved San Francisco on Apple devices, which is the
/// right instinct for a native app and the wrong one for matching Claude,
/// where the point is that the app looks the same on every device.
///
/// **The real typefaces cannot ship here.** Claude's interface face and its
/// serif are licensed commercial fonts; redistributing them inside this app
/// would be a licence breach, not a technicality. **Inter** and **Source
/// Serif 4** are the closest open substitutes and are what actually ship.
/// The proportions, weights and rhythm below are matched; the letterforms are
/// not identical and cannot be. Said plainly here so nobody later reads
/// "identical to Claude" and wonders why the *g* is a different shape.
///
/// | Face | Job |
/// |---|---|
/// | Inter | operating the app — labels, buttons, navigation |
/// | Source Serif 4 | reading at length — replies, notes, generated prose |
/// | monospace | code, diffs, anything columnar |
///
/// ## The scale
///
/// Claude's, which is a comfortable-reading scale rather than a platform one:
/// **16 is body**, headings step gently, and long-form prose gets its own
/// larger, looser setting in [proseStyle]. Tracking is near zero except where
/// display sizes need pulling in — Inter is loose by default at 28pt and up.
class ShiftType {
  const ShiftType._();

  /// The interface face, on every platform. See the note above on why this is
  /// a constant rather than a function of the device.
  static const ui = 'Inter';

  /// Long-form reading.
  static const prose = 'Source Serif 4';

  /// Code, diffs, anything columnar.
  static const code = 'monospace';

  /// Kept as a function so call sites need not change, but the answer no
  /// longer depends on the device — see the note above.
  static String? uiFamilyFor(TargetPlatform platform) => ui;

  /// Inter runs loose at display sizes and needs pulling in; at text sizes it
  /// is already right. One negative step rather than a table, because this is
  /// not trying to reproduce an optically-sized family.
  static double _tracking(double size) {
    if (size >= 28) return -0.8;
    if (size >= 22) return -0.5;
    if (size >= 18) return -0.3;
    return 0.0;
  }

  static TextStyle _style({
    required String? family,
    required double size,
    required double lineHeight,
    required Color color,
    FontWeight weight = FontWeight.w400,
    double? tracking,
  }) =>
      TextStyle(
        fontFamily: family,
        fontSize: size,
        height: lineHeight / size,
        fontWeight: weight,
        letterSpacing: tracking ?? _tracking(size),
        color: color,
      );

  /// [platform] is accepted but no longer changes the face — see above.
  static TextTheme textTheme(
    Color text,
    Color muted, {
    required TargetPlatform platform,
  }) {
    final ui = uiFamilyFor(platform);

    return TextTheme(
      // The greeting on an empty conversation, and nothing else.
      displayLarge: _style(
          family: ui, size: 32, lineHeight: 40, weight: FontWeight.w500,
          color: text),
      displayMedium: _style(
          family: ui, size: 26, lineHeight: 33, weight: FontWeight.w500,
          color: text),

      // Screen and section titles.
      headlineMedium: _style(
          family: ui, size: 20, lineHeight: 27, weight: FontWeight.w600,
          color: text),
      headlineSmall: _style(
          family: ui, size: 17, lineHeight: 24, weight: FontWeight.w600,
          color: text),

      // Row and card titles.
      titleMedium: _style(
          family: ui, size: 15, lineHeight: 21, weight: FontWeight.w600,
          color: text),
      titleSmall: _style(
          family: ui, size: 14, lineHeight: 20, weight: FontWeight.w600,
          color: text),

      // Interface copy. 16 is body — not the 17 a native iOS app would use,
      // and not the 14 Material defaults to.
      bodyLarge: _style(family: ui, size: 16, lineHeight: 24, color: text),
      bodyMedium: _style(family: ui, size: 15, lineHeight: 22, color: text),
      bodySmall: _style(family: ui, size: 13, lineHeight: 19, color: muted),

      // Buttons and chips: text-weight, not shouty.
      labelLarge: _style(
          family: ui, size: 15, lineHeight: 20, weight: FontWeight.w500,
          color: text),
      labelMedium: _style(family: ui, size: 13, lineHeight: 18, color: muted),
      labelSmall: _style(family: ui, size: 12, lineHeight: 16, color: muted),
    );
  }

  /// Long-form reading — a reply, a note, generated prose.
  ///
  /// This is where the serif belongs and the only place it appears. The rule
  /// is unchanged from the Apple pass and survives it: reading at length is a
  /// different activity from operating the app, and the change of face is what
  /// says so. Using it for labels and blurbs made the interface read as a
  /// document.
  ///
  /// Larger and looser than [TextTheme.bodyLarge] because it is measured in
  /// paragraphs rather than in labels.
  static TextStyle proseStyle(Color text) => TextStyle(
        fontFamily: prose,
        fontSize: 17,
        height: 28 / 17,
        color: text,
      );

  /// Code, diffs, and anything columnar.
  static TextStyle codeStyle(Color text, {double size = 13}) => TextStyle(
        fontFamily: code,
        fontSize: size,
        height: 1.5,
        color: text,
        // Ligatures off. `!=` rendering as `≠` is charming in a design tool and
        // actively unhelpful in a diff, where the reader needs to see the
        // characters that are actually in the file.
        fontFeatures: const [FontFeature.disable('liga')],
      );
}
