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
/// The neutrals are **warm** — this is Claude's palette, not a neutral grey
/// one and not Apple's. Paper is a cream off-white rather than #FFF, the greys
/// carry yellow rather than blue, and the accent is the terracotta from
/// Anthropic's own mark. The warmth is most of the identity: swap the cream
/// for white and the same layout stops looking like Claude immediately.
///
/// Two earlier directions are recorded here because they were each right for
/// what was asked and each replaced: a violet-tinted set (brand-derived), and
/// Apple's exact system greys (neutral, for a native-iOS look).
class ShiftPalette {
  const ShiftPalette._();

  /// The app icon's gradient. Kept for the mark itself — the launcher icon and
  /// the boot splash are still the magenta-to-blue plate — but deliberately
  /// absent from the interface, which is Claude's warm set below.
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

  /// Light: cream paper, warm greys, terracotta.
  ///
  /// `ground` is the paper the whole app sits on and `surfaceRaised` is the
  /// near-white a menu or a card lifts to — the opposite way round from a
  /// grey-ground system, and the reason a panel here reads as *lighter* than
  /// its surroundings rather than darker.
  static const light = ShiftColors(
    ground: Color(0xFFFAF9F5),
    surface: Color(0xFFF0EEE6),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEDEAE0),
    divider: Color(0xFFE5E2D9),
    border: Color(0xFFDAD6C9),
    borderFocus: Color(0xFFC15F3C),
    text: Color(0xFF141413),
    textMuted: Color(0xFF6B6961),
    textFaint: Color(0xFF91908A),
    accent: Color(0xFFC15F3C),
    onAccent: Color(0xFFFFFFFF),
    accentWash: Color(0xFFF6EDE7),
    success: Color(0xFF3F7A55),
    warning: Color(0xFF9A6410),
    danger: Color(0xFFB4362F),
    diffAdded: Color(0xFFE8F2E9),
    diffRemoved: Color(0xFFF9E9E7),
  );

  /// Dark: warm charcoal, never black.
  ///
  /// The ground is a brown-grey, not a neutral one and not #000. That is the
  /// whole trick of this dark mode — a true-black ground under the same
  /// terracotta reads as a generic dark theme, and the accent goes muddy
  /// against it. Text is warm off-white for the same reason.
  static const dark = ShiftColors(
    ground: Color(0xFF262624),
    surface: Color(0xFF30302E),
    surfaceRaised: Color(0xFF3A3A37),
    surfaceSunken: Color(0xFF1F1E1D),
    divider: Color(0xFF3E3E3B),
    border: Color(0xFF4A4A46),
    borderFocus: Color(0xFFD97757),
    text: Color(0xFFF5F4EF),
    textMuted: Color(0xFFB0AEA5),
    textFaint: Color(0xFF8A887F),
    accent: Color(0xFFD97757),
    onAccent: Color(0xFF1F1E1D),
    accentWash: Color(0xFF3A2E28),
    success: Color(0xFF6FBF8E),
    warning: Color(0xFFE0A44A),
    danger: Color(0xFFE8776B),
    diffAdded: Color(0xFF1E2E22),
    diffRemoved: Color(0xFF33201E),
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
