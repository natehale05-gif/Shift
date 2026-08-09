import 'package:flutter/material.dart';

/// The type system, and the rule about which face does what.
///
/// Three faces, three jobs, no overlap:
///
/// | Face | Job |
/// |---|---|
/// | **Inter** | operating the app — labels, buttons, navigation, dense lists |
/// | **Source Serif 4** | reading at length — a reply, a note, generated prose |
/// | **monospace** (JetBrains Mono) | code, diffs, anything where columns line up |
///
/// The serif is the part worth defending. An app that spans a chat thread and
/// a code editor risks feeling like two apps bolted together; giving prose its
/// own face is what makes reading feel like a different activity from
/// operating, in the one place where it genuinely is.
class ShiftType {
  const ShiftType._();

  static const ui = 'Inter';
  static const prose = 'Source Serif 4';
  static const code = 'monospace';

  /// A scale, not a set of sizes picked per screen. Ratios are gentle (~1.2)
  /// because the app is dense — a dramatic scale is for a page you read once,
  /// not a tool you live in.
  static TextTheme textTheme(Color text, Color muted) => TextTheme(
        // Reserved for the wordmark and an empty state's headline. Tight
        // tracking, because Inter at display sizes is loose by default and
        // reads as a system dialog until it is pulled in.
        displayLarge: TextStyle(
          fontFamily: ui,
          fontSize: 40,
          height: 1.1,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.0,
          color: text,
        ),
        displayMedium: TextStyle(
          fontFamily: ui,
          fontSize: 30,
          height: 1.15,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
          color: text,
        ),

        // Screen and section titles.
        headlineMedium: TextStyle(
          fontFamily: ui,
          fontSize: 22,
          height: 1.25,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
          color: text,
        ),
        headlineSmall: TextStyle(
          fontFamily: ui,
          fontSize: 18,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: text,
        ),

        // Card and row titles.
        titleMedium: TextStyle(
          fontFamily: ui,
          fontSize: 15,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        titleSmall: TextStyle(
          fontFamily: ui,
          fontSize: 13.5,
          height: 1.35,
          fontWeight: FontWeight.w600,
          color: text,
        ),

        // Interface copy. Not for paragraphs — see [proseStyle].
        bodyLarge: TextStyle(
          fontFamily: ui,
          fontSize: 15,
          height: 1.45,
          color: text,
        ),
        bodyMedium: TextStyle(
          fontFamily: ui,
          fontSize: 14,
          height: 1.45,
          color: text,
        ),
        bodySmall: TextStyle(
          fontFamily: ui,
          fontSize: 12.5,
          height: 1.4,
          color: muted,
        ),

        // Buttons and chips.
        labelLarge: TextStyle(
          fontFamily: ui,
          fontSize: 14,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: text,
        ),
        labelMedium: TextStyle(
          fontFamily: ui,
          fontSize: 12.5,
          height: 1.2,
          fontWeight: FontWeight.w500,
          color: muted,
        ),
        // Uppercase eyebrows get tracking, because caps set at UI sizes
        // without it are a solid block rather than a word.
        labelSmall: TextStyle(
          fontFamily: ui,
          fontSize: 11,
          height: 1.2,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: muted,
        ),
      );

  /// Long-form reading. Larger and looser than [TextTheme.bodyLarge] because
  /// it is measured in paragraphs rather than in labels.
  static TextStyle proseStyle(Color text) => TextStyle(
        fontFamily: prose,
        fontSize: 16.5,
        height: 1.6,
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
