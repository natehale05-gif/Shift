import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

class AppTheme {
  AppTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.light,
      surface: AppColors.lightSurface,
    );
    return _base(
      colorScheme: colorScheme,
      background: AppColors.lightBackground,
      surfaceAlt: AppColors.lightSurfaceAlt,
      border: AppColors.lightBorder,
      textPrimary: AppColors.lightTextPrimary,
      textSecondary: AppColors.lightTextSecondary,
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      surface: AppColors.darkSurface,
    );
    return _base(
      colorScheme: colorScheme,
      background: AppColors.darkBackground,
      surfaceAlt: AppColors.darkSurfaceAlt,
      border: AppColors.darkBorder,
      textPrimary: AppColors.darkTextPrimary,
      textSecondary: AppColors.darkTextSecondary,
    );
  }

  static ThemeData _base({
    required ColorScheme colorScheme,
    required Color background,
    required Color surfaceAlt,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final textTheme = AppTypography.textTheme(textPrimary, textSecondary);
    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      dividerColor: border,
      cardTheme: CardThemeData(
        color: colorScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
          side: BorderSide(color: border),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge,
        iconTheme: IconThemeData(color: textPrimary),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colorScheme.surface,
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        unselectedIconTheme: IconThemeData(color: textSecondary),
        selectedLabelTextStyle:
            textTheme.labelMedium?.copyWith(color: colorScheme.primary),
        unselectedLabelTextStyle: textTheme.labelMedium,
        useIndicator: true,
        indicatorColor: colorScheme.primaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStatePropertyAll(textTheme.labelSmall),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          borderSide: BorderSide.none,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xl,
            vertical: AppSpacing.md,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceAlt,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        ),
        labelStyle: textTheme.labelMedium?.copyWith(color: textPrimary),
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 6),
      ),
      extensions: [
        AppSemanticColors(
          border: border,
          surfaceAlt: surfaceAlt,
          textSecondary: textSecondary,
          warningSurface: colorScheme.brightness == Brightness.light
              ? AppColors.warningSurfaceLight
              : AppColors.warningSurfaceDark,
          warningText: colorScheme.brightness == Brightness.light
              ? AppColors.warningText
              : AppColors.warningTextDark,
        ),
      ],
    );
  }
}

/// Extra semantic colors not modeled by [ColorScheme], reachable via
/// `Theme.of(context).extension<AppSemanticColors>()`.
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  final Color border;
  final Color surfaceAlt;
  final Color textSecondary;
  final Color warningSurface;
  final Color warningText;

  const AppSemanticColors({
    required this.border,
    required this.surfaceAlt,
    required this.textSecondary,
    required this.warningSurface,
    required this.warningText,
  });

  @override
  AppSemanticColors copyWith({
    Color? border,
    Color? surfaceAlt,
    Color? textSecondary,
    Color? warningSurface,
    Color? warningText,
  }) {
    return AppSemanticColors(
      border: border ?? this.border,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      textSecondary: textSecondary ?? this.textSecondary,
      warningSurface: warningSurface ?? this.warningSurface,
      warningText: warningText ?? this.warningText,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      border: Color.lerp(border, other.border, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
      warningText: Color.lerp(warningText, other.warningText, t)!,
    );
  }
}
