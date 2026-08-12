import 'package:flutter/material.dart';

import 'metrics.dart';
import 'palette.dart';
import 'typography.dart';

/// Builds the two themes from the tokens.
///
/// Material's own [ColorScheme] is filled in as well, because framework
/// widgets read it whether or not we do — a [Switch] or a [TextField] left to
/// the default scheme will paint Material purple next to our accent and look
/// like a mistake. So the scheme is derived from the same tokens rather than
/// left to `ColorScheme.fromSeed`, which would invent its own values.
/// [platform] is not optional and not inferable here: on iOS and macOS the UI
/// face is the system font (a null family), and everywhere else it is bundled
/// Inter. A default would silently ship Inter to an iPhone, which is the exact
/// thing this design direction exists to stop.
ThemeData shiftTheme(Brightness brightness, TargetPlatform platform) {
  final uiFamily = ShiftType.uiFamilyFor(platform);
  final c = brightness == Brightness.dark ? ShiftColors.dark : ShiftColors.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    primaryContainer: c.accentWash,
    onPrimaryContainer: c.text,
    secondary: c.accent,
    onSecondary: c.onAccent,
    error: c.danger,
    onError: brightness == Brightness.dark
        ? const Color(0xFF16111F)
        : const Color(0xFFFFFFFF),
    surface: c.surface,
    onSurface: c.text,
    onSurfaceVariant: c.textMuted,
    outline: c.border,
    outlineVariant: c.divider,
  );

  // Merged onto the platform's own text theme and then forced onto the
  // bundled family, rather than handed over as a replacement.
  //
  // A [TextTheme] with gaps is not "mostly right": every slot it omits —
  // titleLarge, displaySmall, headlineLarge — resolves to Material's default
  // typography, which is Roboto, which the web build then **downloads from
  // fonts.gstatic.com at runtime**. That is a third-party request on first
  // paint, a privacy disclosure both stores ask about, and a blank line of
  // text for anyone offline. Found by watching the network rather than by
  // reading the theme.
  final text =
      ShiftType.textTheme(c.text, c.textMuted, platform: platform);

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    // Set here rather than by a later copyWith, because the text theme above
    // was already resolved against it. A theme whose `platform` disagrees with
    // the face it carries is the subtle version of this bug.
    platform: platform,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.ground,
    canvasColor: c.ground,
    dividerColor: c.divider,
    extensions: [c],
    fontFamily: uiFamily,

    // Every ink splash in the app, off. A ripple that travels a card's width
    // is a Material signature, and this app is not trying to look like
    // Material — it wants the immediate, quiet press states below.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,

    dividerTheme: DividerThemeData(
      color: c.divider,
      thickness: 1,
      space: 1,
    ),

    iconTheme: IconThemeData(color: c.textMuted, size: 20),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size(0, kMinTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        // Not const: the family is now resolved per platform. 17pt because a
        // button on iOS is body-sized text, not the 14pt Material label this
        // carried before — the single change that most makes controls stop
        // looking undersized on a phone.
        textStyle: TextStyle(
          fontFamily: uiFamily,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        minimumSize: const Size(0, kMinTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        side: BorderSide(color: c.border),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        // Not const: the family is now resolved per platform. 17pt because a
        // button on iOS is body-sized text, not the 14pt Material label this
        // carried before — the single change that most makes controls stop
        // looking undersized on a phone.
        textStyle: TextStyle(
          fontFamily: uiFamily,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.accent,
        minimumSize: const Size(0, kMinTouchTarget),
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        // Not const: the family is now resolved per platform. 17pt because a
        // button on iOS is body-sized text, not the 14pt Material label this
        // carried before — the single change that most makes controls stop
        // looking undersized on a phone.
        textStyle: TextStyle(
          fontFamily: uiFamily,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),

    // Comfortable rather than compact: this is the field people type their
    // whole request into, on a phone, one-handed.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      hintStyle: TextStyle(fontFamily: uiFamily, color: c.textFaint),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: c.borderFocus, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        borderSide: BorderSide(color: c.danger),
      ),
    ),

    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.md),
        side: BorderSide(color: c.border),
      ),
    ),

    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: c.border),
      ),
      textStyle: TextStyle(
        fontFamily: uiFamily,
        fontSize: 12,
        color: c.text,
      ),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surfaceRaised,
      contentTextStyle: TextStyle(fontFamily: uiFamily, color: c.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
    ),

    // The tab-key focus ring. Visible by default rather than opt-in, because
    // both stores' accessibility reviews look for it and, more to the point,
    // Code mode is keyboard-driven and unusable without it.
    focusColor: c.borderFocus,
  );

  return base.copyWith(
    textTheme: base.textTheme.merge(text).apply(fontFamily: uiFamily),
    primaryTextTheme:
        base.primaryTextTheme.merge(text).apply(fontFamily: uiFamily),
  );
}
