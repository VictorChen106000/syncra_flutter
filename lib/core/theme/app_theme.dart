import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../constants/app_colors.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get lightTheme {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.scaffold,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accent,
        primary: AppColors.ink,
        secondary: AppColors.accent,
        surface: AppColors.surface,
      ),
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    final inter = GoogleFonts.interTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: inter.copyWith(
        displayLarge: inter.displayLarge?.copyWith(
          color: AppColors.ink,
          fontSize: 44,
          fontWeight: FontWeight.w900,
          height: 1.05,
          letterSpacing: -1.4,
        ),
        headlineLarge: inter.headlineLarge?.copyWith(
          color: AppColors.ink,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          height: 1.05,
          letterSpacing: -1.2,
        ),
        headlineMedium: inter.headlineMedium?.copyWith(
          color: AppColors.ink,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        titleLarge: inter.titleLarge?.copyWith(
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: inter.titleMedium?.copyWith(
          color: AppColors.ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: inter.bodyLarge?.copyWith(
          color: AppColors.ink,
          fontSize: 14.5,
          height: 1.55,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: inter.bodyMedium?.copyWith(
          color: AppColors.textMuted,
          fontSize: 13,
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
        labelLarge: inter.labelLarge?.copyWith(
          color: AppColors.ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.accent : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.ink : AppColors.border,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
    );
  }
}
