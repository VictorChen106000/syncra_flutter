import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'brand_theme.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData get lightTheme => _build(BrandTheme.light);
  static ThemeData get darkTheme => _build(BrandTheme.dark);

  static ThemeData _build(BrandTheme brand) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brand.brightness,
      scaffoldBackgroundColor: brand.bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: brand.accent,
        brightness: brand.brightness,
        primary: brand.ink,
        secondary: brand.accent,
        surface: brand.surface,
        error: brand.danger,
      ),
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.standard,
      extensions: [brand],
    );

    final inter = GoogleFonts.interTextTheme(base.textTheme);

    return base.copyWith(
      textTheme: inter.copyWith(
        displayLarge: inter.displayLarge?.copyWith(
          color: brand.ink,
          fontSize: 44,
          fontWeight: FontWeight.w900,
          height: 1.05,
          letterSpacing: -1.4,
        ),
        headlineLarge: inter.headlineLarge?.copyWith(
          color: brand.ink,
          fontSize: 32,
          fontWeight: FontWeight.w800,
          height: 1.05,
          letterSpacing: -1.2,
        ),
        headlineMedium: inter.headlineMedium?.copyWith(
          color: brand.ink,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.6,
        ),
        titleLarge: inter.titleLarge?.copyWith(
          color: brand.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        titleMedium: inter.titleMedium?.copyWith(
          color: brand.ink,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: inter.bodyLarge?.copyWith(
          color: brand.ink,
          fontSize: 14.5,
          height: 1.55,
          fontWeight: FontWeight.w500,
        ),
        bodyMedium: inter.bodyMedium?.copyWith(
          color: brand.textMuted,
          fontSize: 13,
          height: 1.5,
          fontWeight: FontWeight.w500,
        ),
        labelLarge: inter.labelLarge?.copyWith(
          color: brand.ink,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? brand.onAccent
              : brand.surface,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? brand.accent
              : brand.border,
        ),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: brand.ink,
        contentTextStyle: TextStyle(
          color: brand.inkInverse,
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
        ),
        actionTextColor: brand.accent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        elevation: 4,
      ),
      dividerTheme: DividerThemeData(
        color: brand.border,
        space: 1,
        thickness: 1,
      ),
      iconTheme: IconThemeData(color: brand.ink),
      focusColor: brand.accent,
    );
  }
}
