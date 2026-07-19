import 'package:flutter/material.dart';

/// Palette built from Apple's own system color values (the same named
/// constants iOS/macOS ship — systemIndigo, systemGray6, label/secondaryLabel,
/// etc.) so the chrome and tint read as authentically "Apple" rather than an
/// approximation.
class AppColors {
  AppColors._();

  /// Apple's systemIndigo (dark-mode value — vivid enough to read well on
  /// both light and dark surfaces as this app's single tint color).
  static const Color accent = Color(0xFF5E5CE6);

  // Apple systemGray6 / systemBackground / label / secondaryLabel (light).
  static const Color lightBackground = Color(0xFFF5F5F7);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceAlt = Color(0xFFF0F0F2);
  static const Color lightBorder = Color(0xFFE3E3E6);
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

  // Apple system colors used as the five studios' accent hues.
  static const Color systemPink = Color(0xFFFF375F);
  static const Color systemBlue = Color(0xFF0A84FF);
  static const Color systemGreen = Color(0xFF30D158);
  static const Color systemOrange = Color(0xFFFF9F0A);
  static const Color systemPurple = Color(0xFFBF5AF2);
}
