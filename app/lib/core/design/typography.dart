import 'package:flutter/material.dart';

/// The type system, on Apple's scale.
///
/// ## The face
///
/// On iOS and macOS the UI face is **the system font** — San Francisco —
/// reached by leaving `fontFamily` null, which is how Flutter resolves
/// `.SF Pro Text`. Not a lookalike: SF is optically sized, its numerals align,
/// and it is the single strongest signal that an app belongs on the device.
/// Bundling a substitute there would be shipping a worse copy of a font the
/// phone already has, and paying for it in download size.
///
/// Everywhere else — Android, web, Windows, Linux — SF is neither present nor
/// licensed for redistribution, so **Inter** stands in. It was drawn against
/// the same brief and is the closest thing that can legally ship. CanvasKit
/// renders only bundled bytes and will not fall back to a CSS stack, so on the
/// web this must be a real bundled family or it is tofu.
///
/// [uiFamilyFor] is therefore a function of the platform rather than a
/// constant, which is the one wrinkle this file exists to hide.
///
/// ## The scale
///
/// Apple's, not an invented one: 34 / 28 / 22 / 20 / 17 / 16 / 15 / 13 / 12,
/// with SF's own tracking at each size — display sizes tighten, small sizes
/// loosen. Guessing at these is what makes an app read as *nearly* native,
/// which is worse than not trying.
///
/// **17pt is body.** Every other platform's default is 14–16, and it is the
/// difference most often missed: a 14pt iOS app looks cramped in a way people
/// notice without being able to name.
class ShiftType {
  const ShiftType._();

  /// Inter, for platforms without SF.
  static const fallbackUi = 'Inter';

  /// Long-form reading.
  static const prose = 'Source Serif 4';

  /// Code, diffs, anything columnar.
  static const code = 'monospace';

  /// Null on Apple platforms, so Flutter resolves the real system font.
  static String? uiFamilyFor(TargetPlatform platform) => switch (platform) {
        TargetPlatform.iOS || TargetPlatform.macOS => null,
        _ => fallbackUi,
      };

  /// SF's optical tracking, which is a table rather than a formula: it goes
  /// negative above ~20pt and positive below ~15pt. Applying one letterSpacing
  /// across a scale is the giveaway that a type system was set by hand.
  static double _tracking(double size) {
    if (size >= 34) return 0.37;
    if (size >= 28) return 0.36;
    if (size >= 22) return 0.35;
    if (size >= 20) return 0.38;
    if (size >= 17) return -0.43;
    if (size >= 16) return -0.32;
    if (size >= 15) return -0.23;
    if (size >= 13) return -0.08;
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

  /// [platform] decides the face; the sizes never change.
  static TextTheme textTheme(
    Color text,
    Color muted, {
    required TargetPlatform platform,
  }) {
    final ui = uiFamilyFor(platform);

    return TextTheme(
      // Large Title — the one that scrolls up into a nav bar.
      displayLarge: _style(
          family: ui,
          size: 34,
          lineHeight: 41,
          weight: FontWeight.w700,
          color: text),
      // Title 1.
      displayMedium: _style(
          family: ui,
          size: 28,
          lineHeight: 34,
          weight: FontWeight.w700,
          color: text),
      // Title 2.
      headlineMedium: _style(
          family: ui,
          size: 22,
          lineHeight: 28,
          weight: FontWeight.w600,
          color: text),
      // Title 3.
      headlineSmall: _style(
          family: ui,
          size: 20,
          lineHeight: 25,
          weight: FontWeight.w600,
          color: text),

      // Headline — body size, semibold. The row title in a grouped list.
      titleMedium: _style(
          family: ui,
          size: 17,
          lineHeight: 22,
          weight: FontWeight.w600,
          color: text),
      // Subhead.
      titleSmall: _style(
          family: ui,
          size: 15,
          lineHeight: 20,
          weight: FontWeight.w600,
          color: text),

      // Body. The default, and it is 17.
      bodyLarge:
          _style(family: ui, size: 17, lineHeight: 22, color: text),
      // Callout.
      bodyMedium:
          _style(family: ui, size: 16, lineHeight: 21, color: text),
      // Footnote.
      bodySmall:
          _style(family: ui, size: 13, lineHeight: 18, color: muted),

      // Buttons take body size and weight, because on iOS they are text.
      labelLarge: _style(
          family: ui,
          size: 17,
          lineHeight: 22,
          weight: FontWeight.w600,
          color: text),
      // Caption 1.
      labelMedium:
          _style(family: ui, size: 12, lineHeight: 16, color: muted),
      // Caption 2.
      labelSmall: _style(
          family: ui, size: 11, lineHeight: 13, color: muted, tracking: 0.06),
    );
  }

  /// Long-form reading — a reply, a note, generated prose.
  ///
  /// The serif survives the move to Apple's system, but only here. It is now
  /// the *exception*, not a second UI face: platform interface copy is SF, and
  /// prose gets its own face for the same reason Books and News do — reading
  /// at length is a different activity from operating, and the change of face
  /// is what says so. Using it for labels and blurbs, as this app did, is what
  /// made the interface read as a document.
  static TextStyle proseStyle(Color text) => TextStyle(
        fontFamily: prose,
        fontSize: 17,
        height: 26 / 17,
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
