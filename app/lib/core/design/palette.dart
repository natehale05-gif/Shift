import 'package:flutter/material.dart';

/// Every colour the app is allowed to use, in both themes.
///
/// One rule, enforced by `tool/scan_raw_colors.py`: **no widget names a colour
/// literal.** They read tokens off the theme. The reason is not tidiness — it
/// is that a hex typed into a widget is invisible to the other theme, and the
/// bug it causes (white text on a white card, once, in dark mode, on one
/// screen) is the kind nobody finds until a user does.
///
/// ## Where the palette comes from
///
/// The brand is a magenta-to-blue gradient on a near-black plate — the app
/// icon. So the accent is not chosen, it is *derived*: [magenta] and [blue] are
/// the gradient's ends, and the solid accent is the point along it that stays
/// legible as text on both grounds, which is not the midpoint.
///
/// The neutrals are deliberately **not** grey. Each carries a slight violet
/// bias toward the accent, which is what makes a surface read as part of the
/// brand rather than as the default Material card that happens to sit near it.
class ShiftPalette {
  const ShiftPalette._();

  /// The gradient ends. Used together — for the mark, for a progress sweep,
  /// for the one accent moment on a screen — and never as a background behind
  /// body text, where a gradient makes contrast unknowable.
  static const magenta = Color(0xFFD648E8);
  static const blue = Color(0xFF4A7DFF);

  static const gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [magenta, blue],
  );
}

/// The resolved token set for one theme.
///
/// Held as a [ThemeExtension] rather than crammed into [ColorScheme] because
/// the app needs distinctions Material does not model — the difference between
/// a raised surface and a sunken one, a border and a divider, prose text and
/// the label above it — and forcing those through `surfaceContainerHighest`
/// and friends is how they stop meaning anything.
@immutable
class ShiftColors extends ThemeExtension<ShiftColors> {
  /// The page behind everything.
  final Color ground;

  /// A card, sheet, or panel sitting on [ground].
  final Color surface;

  /// A surface on a surface — a menu over a panel, an input inside a card.
  final Color surfaceRaised;

  /// A well: code blocks, diff gutters, anything that reads as recessed.
  final Color surfaceSunken;

  /// A hairline that separates. Lower contrast than [border] on purpose.
  final Color divider;

  /// The outline of an interactive thing — a field, a chip, a button.
  final Color border;

  /// The outline of the thing that currently has focus.
  final Color borderFocus;

  /// Body text and anything that must be read comfortably at length.
  final Color text;

  /// Labels, captions, timestamps, placeholder text.
  final Color textMuted;

  /// Text that is present but deliberately quiet — disabled, or a hint.
  final Color textFaint;

  /// The one accent. Links, selection, the primary action, the active tab.
  final Color accent;

  /// Accent text *on* an accent fill.
  final Color onAccent;

  /// A wash of the accent, for a selected row or an active mode.
  final Color accentWash;

  /// Semantic, and separate from [accent] on purpose: a green that means
  /// "this succeeded" must not be the same colour as "this is selected", or
  /// neither statement can be read.
  final Color success;
  final Color warning;
  final Color danger;

  /// Diff review, which is Code mode's whole reason for existing. Kept in the
  /// palette rather than in that feature, because Design and Work show diffs
  /// of documents too and they must not drift to a second green.
  final Color diffAdded;
  final Color diffRemoved;

  const ShiftColors({
    required this.ground,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceSunken,
    required this.divider,
    required this.border,
    required this.borderFocus,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.accent,
    required this.onAccent,
    required this.accentWash,
    required this.success,
    required this.warning,
    required this.danger,
    required this.diffAdded,
    required this.diffRemoved,
  });

  /// Warm off-white rather than paper white, biased a few degrees violet so it
  /// sits under the accent instead of beside it.
  static const light = ShiftColors(
    ground: Color(0xFFFBFAFD),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFF4F1F9),
    divider: Color(0xFFEDE9F4),
    border: Color(0xFFE0DAEC),
    borderFocus: Color(0xFF8B3FD6),
    text: Color(0xFF16111F),
    textMuted: Color(0xFF6B6280),
    textFaint: Color(0xFF9A93AB),
    accent: Color(0xFF8B3FD6),
    onAccent: Color(0xFFFFFFFF),
    accentWash: Color(0xFFF3EAFC),
    success: Color(0xFF1F7A55),
    warning: Color(0xFF9A6410),
    danger: Color(0xFFC0332F),
    diffAdded: Color(0xFFE6F6ED),
    diffRemoved: Color(0xFFFCEBEA),
  );

  /// The ground is the icon's own plate, so the app and its icon are the same
  /// object. Surfaces lift by lightness *and* a touch more saturation, which
  /// reads as depth where a pure lightness step reads as haze.
  static const dark = ShiftColors(
    ground: Color(0xFF0A0714),
    surface: Color(0xFF141020),
    surfaceRaised: Color(0xFF1D1730),
    surfaceSunken: Color(0xFF070510),
    divider: Color(0xFF221B36),
    border: Color(0xFF2E2547),
    borderFocus: Color(0xFFB76BFF),
    text: Color(0xFFF2EFF7),
    textMuted: Color(0xFFA79CBF),
    textFaint: Color(0xFF6F6688),
    accent: Color(0xFFB76BFF),
    onAccent: Color(0xFF16111F),
    accentWash: Color(0xFF231A38),
    success: Color(0xFF4FC08D),
    warning: Color(0xFFE0A44A),
    danger: Color(0xFFF07069),
    diffAdded: Color(0xFF122A1F),
    diffRemoved: Color(0xFF2E1618),
  );

  @override
  ShiftColors copyWith({
    Color? ground,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceSunken,
    Color? divider,
    Color? border,
    Color? borderFocus,
    Color? text,
    Color? textMuted,
    Color? textFaint,
    Color? accent,
    Color? onAccent,
    Color? accentWash,
    Color? success,
    Color? warning,
    Color? danger,
    Color? diffAdded,
    Color? diffRemoved,
  }) =>
      ShiftColors(
        ground: ground ?? this.ground,
        surface: surface ?? this.surface,
        surfaceRaised: surfaceRaised ?? this.surfaceRaised,
        surfaceSunken: surfaceSunken ?? this.surfaceSunken,
        divider: divider ?? this.divider,
        border: border ?? this.border,
        borderFocus: borderFocus ?? this.borderFocus,
        text: text ?? this.text,
        textMuted: textMuted ?? this.textMuted,
        textFaint: textFaint ?? this.textFaint,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        accentWash: accentWash ?? this.accentWash,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        danger: danger ?? this.danger,
        diffAdded: diffAdded ?? this.diffAdded,
        diffRemoved: diffRemoved ?? this.diffRemoved,
      );

  @override
  ShiftColors lerp(ThemeExtension<ShiftColors>? other, double t) {
    if (other is! ShiftColors) return this;
    return ShiftColors(
      ground: Color.lerp(ground, other.ground, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderFocus: Color.lerp(borderFocus, other.borderFocus, t)!,
      text: Color.lerp(text, other.text, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textFaint: Color.lerp(textFaint, other.textFaint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      accentWash: Color.lerp(accentWash, other.accentWash, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      diffAdded: Color.lerp(diffAdded, other.diffAdded, t)!,
      diffRemoved: Color.lerp(diffRemoved, other.diffRemoved, t)!,
    );
  }
}

/// Reads the tokens. Every widget in the app goes through here.
extension ShiftColorsOf on BuildContext {
  ShiftColors get colors => Theme.of(this).extension<ShiftColors>()!;
}
