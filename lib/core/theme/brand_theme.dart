import 'package:flutter/material.dart';

/// Semantic design tokens for both light and dark modes.
///
/// Polished widgets and pages read from `Theme.of(context).extension<BrandTheme>()!`
/// instead of the legacy `AppColors` constants.
@immutable
class BrandTheme extends ThemeExtension<BrandTheme> {
  const BrandTheme({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceMuted,
    required this.surfaceSubtle,
    required this.border,
    required this.outline,
    required this.ink,
    required this.inkInverse,
    required this.textMuted,
    required this.textSoft,
    required this.accent,
    required this.accentBright,
    required this.accentMuted,
    required this.onAccent,
    required this.danger,
    required this.warning,
    required this.success,
    required this.shadow,
    required this.glassFill,
    required this.glassBorder,
  });

  final Brightness brightness;

  final Color bg;
  final Color surface;
  final Color surfaceMuted;
  final Color surfaceSubtle;
  final Color border;
  final Color outline;

  final Color ink;
  final Color inkInverse;
  final Color textMuted;
  final Color textSoft;

  final Color accent;
  final Color accentBright;
  final Color accentMuted;
  final Color onAccent;

  final Color danger;
  final Color warning;
  final Color success;

  final Color shadow;
  final Color glassFill;
  final Color glassBorder;

  bool get isDark => brightness == Brightness.dark;

  static BrandTheme of(BuildContext context) {
    final t = Theme.of(context).extension<BrandTheme>();
    return t ?? light;
  }

  static const light = BrandTheme(
    brightness: Brightness.light,
    bg: Color(0xFFF2F4F3),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF4F5F4),
    surfaceSubtle: Color(0xFFFAFAFA),
    border: Color(0xFFDEE1E0),
    outline: Color(0xFFC8CCCB),
    ink: Color(0xFF0A0B0A),
    inkInverse: Color(0xFFFFFFFF),
    textMuted: Color(0xFF5E6361),
    textSoft: Color(0xFF8E9290),
    accent: Color(0xFFA0FE08),
    accentBright: Color(0xFFB7FF3A),
    accentMuted: Color(0x33A0FE08),
    onAccent: Color(0xFF0A0B0A),
    danger: Color(0xFFE5484D),
    warning: Color(0xFFF5A524),
    success: Color(0xFF16A34A),
    shadow: Color(0x140A0B0A),
    glassFill: Color(0xCCFFFFFF),
    glassBorder: Color(0x66FFFFFF),
  );

  static const dark = BrandTheme(
    brightness: Brightness.dark,
    bg: Color(0xFF0B0B0D),
    surface: Color(0xFF16171A),
    surfaceMuted: Color(0xFF1E2024),
    surfaceSubtle: Color(0xFF101114),
    border: Color(0xFF2A2D32),
    outline: Color(0xFF3A3E44),
    ink: Color(0xFFF5F7F6),
    inkInverse: Color(0xFF0A0B0A),
    textMuted: Color(0xFFA6A9AD),
    textSoft: Color(0xFF6E7177),
    accent: Color(0xFFA0FE08),
    accentBright: Color(0xFFB7FF3A),
    accentMuted: Color(0x33A0FE08),
    onAccent: Color(0xFF0A0B0A),
    danger: Color(0xFFFF6B62),
    warning: Color(0xFFFFC857),
    success: Color(0xFF4ADE80),
    shadow: Color(0x66000000),
    glassFill: Color(0xCC16171A),
    glassBorder: Color(0x332A2D32),
  );

  @override
  BrandTheme copyWith({
    Brightness? brightness,
    Color? bg,
    Color? surface,
    Color? surfaceMuted,
    Color? surfaceSubtle,
    Color? border,
    Color? outline,
    Color? ink,
    Color? inkInverse,
    Color? textMuted,
    Color? textSoft,
    Color? accent,
    Color? accentBright,
    Color? accentMuted,
    Color? onAccent,
    Color? danger,
    Color? warning,
    Color? success,
    Color? shadow,
    Color? glassFill,
    Color? glassBorder,
  }) {
    return BrandTheme(
      brightness: brightness ?? this.brightness,
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      surfaceSubtle: surfaceSubtle ?? this.surfaceSubtle,
      border: border ?? this.border,
      outline: outline ?? this.outline,
      ink: ink ?? this.ink,
      inkInverse: inkInverse ?? this.inkInverse,
      textMuted: textMuted ?? this.textMuted,
      textSoft: textSoft ?? this.textSoft,
      accent: accent ?? this.accent,
      accentBright: accentBright ?? this.accentBright,
      accentMuted: accentMuted ?? this.accentMuted,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      warning: warning ?? this.warning,
      success: success ?? this.success,
      shadow: shadow ?? this.shadow,
      glassFill: glassFill ?? this.glassFill,
      glassBorder: glassBorder ?? this.glassBorder,
    );
  }

  @override
  BrandTheme lerp(ThemeExtension<BrandTheme>? other, double t) {
    if (other is! BrandTheme) return this;
    return BrandTheme(
      brightness: t < 0.5 ? brightness : other.brightness,
      bg: Color.lerp(bg, other.bg, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      surfaceSubtle: Color.lerp(surfaceSubtle, other.surfaceSubtle, t)!,
      border: Color.lerp(border, other.border, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkInverse: Color.lerp(inkInverse, other.inkInverse, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      textSoft: Color.lerp(textSoft, other.textSoft, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentBright: Color.lerp(accentBright, other.accentBright, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      success: Color.lerp(success, other.success, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
    );
  }
}

extension BrandThemeOnContext on BuildContext {
  BrandTheme get brand => BrandTheme.of(this);
}
