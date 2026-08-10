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
/// The neutrals **are** grey — Apple's, exactly. They used to carry a violet
/// bias toward the accent on the reasoning that a tinted surface reads as part
/// of the brand; on a device it read as an app that had been colour-shifted,
/// because every real control beside it is neutral. The accent carries the
/// brand and the paper stays out of the way, which is what Apple's own apps
/// do: Music is pink, Notes is yellow, and neither tints its background.
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

  /// Light mode, on iOS's own greys.
  ///
  /// `ground` is `systemBackground` and `surface` is
  /// `secondarySystemBackground` — the pairing a *content* screen uses. The
  /// grouped pair (grey behind, white cards) is for Settings-style lists and
  /// is wrong here: it made the whole app read as one flat sheet of grey, with
  /// nothing to lift a card off. Checked by looking at it rather than by
  /// picking the first plausible entry in the colour list.
  ///
  /// Separators are the real hairline values, not a light grey chosen by eye.
  ///
  /// **The neutrals used to carry a violet bias**, on the reasoning that a
  /// tinted surface reads as part of the brand. It also read as *not Apple*:
  /// the platform's greys are neutral, so a purple-cast white beside a real
  /// system control looks like a colour-managed screenshot. The accent below
  /// carries the brand instead, which is what Apple's own apps do — Music is
  /// pink, Notes is yellow, and neither tints its paper.
  static const light = ShiftColors(
    ground: Color(0xFFFFFFFF),
    surface: Color(0xFFF2F2F7),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFE5E5EA),
    divider: Color(0xFFC6C6C8),
    border: Color(0xFFD1D1D6),
    borderFocus: Color(0xFF8944D6),
    text: Color(0xFF000000),
    textMuted: Color(0xFF6C6C70),
    textFaint: Color(0xFF8E8E93),
    accent: Color(0xFF8944D6),
    onAccent: Color(0xFFFFFFFF),
    accentWash: Color(0xFFF1E9FB),
    success: Color(0xFF248A3D),
    warning: Color(0xFFB25000),
    danger: Color(0xFFD70015),
    diffAdded: Color(0xFFE8F6EC),
    diffRemoved: Color(0xFFFDECEC),
  );

  /// Dark mode, likewise.
  ///
  /// True black ground rather than the icon's near-black plate: on an OLED
  /// iPhone that is what the platform does, and it is what makes an inset card
  /// at `#1C1C1E` read as a card at all. Text is `#FFFFFF` and the two muted
  /// steps are `secondaryLabel` and `tertiaryLabel`, so the hierarchy matches
  /// every other app on the device rather than approximating it.
  static const dark = ShiftColors(
    ground: Color(0xFF000000),
    surface: Color(0xFF1C1C1E),
    surfaceRaised: Color(0xFF2C2C2E),
    surfaceSunken: Color(0xFF0A0A0C),
    divider: Color(0xFF38383A),
    border: Color(0xFF48484A),
    borderFocus: Color(0xFFBF5AF2),
    text: Color(0xFFFFFFFF),
    textMuted: Color(0xFF98989F),
    textFaint: Color(0xFF6C6C70),
    accent: Color(0xFFBF5AF2),
    onAccent: Color(0xFFFFFFFF),
    accentWash: Color(0xFF2A1B38),
    success: Color(0xFF30D158),
    warning: Color(0xFFFF9F0A),
    danger: Color(0xFFFF453A),
    diffAdded: Color(0xFF102A18),
    diffRemoved: Color(0xFF2E1416),
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
