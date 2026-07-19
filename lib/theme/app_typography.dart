import 'package:flutter/material.dart';

/// Uses the platform/browser's default sans-serif stack rather than a
/// network-fetched web font — this app has no backend and ships to static
/// GitHub Pages hosting, so it shouldn't depend on an external font CDN
/// (and on some networks a blocked CDN fetch would silently blank all text).
/// The custom weights/spacing below still give it a deliberate, Apple-HIG-
/// adjacent feel without that dependency.
class AppTypography {
  AppTypography._();

  static TextTheme textTheme(Color primary, Color secondary) {
    final base = Typography.blackMountainView.apply(fontFamily: 'Roboto');
    return base
        .copyWith(
          displayLarge: base.displayLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -1.0,
            color: primary,
          ),
          displayMedium: base.displayMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.6,
            color: primary,
          ),
          headlineLarge: base.headlineLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: primary,
          ),
          headlineMedium: base.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: primary,
          ),
          titleLarge: base.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: primary,
          ),
          titleMedium: base.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: primary,
          ),
          bodyLarge: base.bodyLarge?.copyWith(color: primary, height: 1.4),
          bodyMedium: base.bodyMedium?.copyWith(color: primary, height: 1.4),
          bodySmall: base.bodySmall?.copyWith(color: secondary),
          labelLarge: base.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: primary,
          ),
          labelMedium: base.labelMedium?.copyWith(color: secondary),
          labelSmall: base.labelSmall?.copyWith(color: secondary),
        );
  }
}
