import 'package:flutter/material.dart';

/// Palette blending Apple's system color values (systemIndigo, systemGray6,
/// true-black dark surfaces) with Anthropic's warm-paper-and-terracotta
/// identity, so the app reads as if the two companies designed it together:
/// warm paper surfaces and a terracotta tint by day, Apple true black by
/// night, Apple system colors for the studio accents throughout.
class AppColors {
  AppColors._();

  /// Anthropic terracotta — the app's tint color (links, send button,
  /// selection states).
  static const Color accent = Color(0xFFD97757);

  /// Lightened terracotta with enough contrast against true-black surfaces.
  static const Color accentDark = Color(0xFFE08B6D);

  /// Apple's systemIndigo, kept for the middleware/routing identity (the
  /// "Shift routes your request" chip) now that terracotta owns the tint.
  static const Color systemIndigo = Color(0xFF5E5CE6);

  // Anthropic warm paper (light).
  static const Color lightBackground = Color(0xFFF5F4EF);
  static const Color lightSurface = Color(0xFFFCFBF8);
  static const Color lightSurfaceAlt = Color(0xFFEFEDE6);
  static const Color lightBorder = Color(0xFFE5E2D9);
  static const Color lightTextPrimary = Color(0xFF1D1D1F);
  static const Color lightTextSecondary = Color(0xFF6E6E73);

  // Apple true-black systemBackground / secondarySystemBackground (dark).
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSurface = Color(0xFF1C1C1E);
  static const Color darkSurfaceAlt = Color(0xFF2C2C2E);
  static const Color darkBorder = Color(0xFF38383A);
  static const Color darkTextPrimary = Color(0xFFF5F5F7);
  static const Color darkTextSecondary = Color(0xFF98989D);

  static const Color warningSurfaceLight = Color(0xFFFFF3D6);
  static const Color warningSurfaceDark = Color(0xFF3A2E10);
  static const Color warningText = Color(0xFF8A5A00);
  static const Color warningTextDark = Color(0xFFE8B948);

  // Apple system colors used as the six studios' accent hues.
  static const Color systemPink = Color(0xFFFF375F);
  static const Color systemBlue = Color(0xFF0A84FF);
  static const Color systemGreen = Color(0xFF30D158);
  static const Color systemOrange = Color(0xFFFF9F0A);
  static const Color systemPurple = Color(0xFFBF5AF2);
  static const Color systemTeal = Color(0xFF40C8E0);
}
