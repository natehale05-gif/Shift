import 'package:flutter/material.dart';

/// Inter (SIL Open Font License, freely redistributable), bundled locally
/// rather than fetched from a font CDN at runtime — this app has no backend
/// and ships to static GitHub Pages hosting, so it shouldn't depend on an
/// external font service (and on some networks a blocked CDN fetch would
/// silently blank all text). Inter's proportions read close to SF Pro's,
/// and the tightened tracking below leans further into that Apple-HIG feel
/// without using Apple's own (non-redistributable) typeface.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Color primary, Color secondary) {
    final base = Typography.blackMountainView.apply(fontFamily: 'Inter');
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1.2,
        height: 1.05,
        color: primary,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        height: 1.08,
        color: primary,
      ),
      headlineLarge: base.headlineLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
        height: 1.15,
        color: primary,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.4,
        height: 1.2,
        color: primary,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: primary,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: primary,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: primary,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        color: primary,
        letterSpacing: -0.2,
        height: 1.45,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: primary,
        letterSpacing: -0.15,
        height: 1.45,
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: secondary,
        letterSpacing: -0.1,
        height: 1.4,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: primary,
      ),
      labelMedium: base.labelMedium?.copyWith(
        color: secondary,
        letterSpacing: -0.05,
      ),
      labelSmall: base.labelSmall?.copyWith(color: secondary),
    );
  }
}
