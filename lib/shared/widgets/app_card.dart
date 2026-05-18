import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/brand_theme.dart';

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppConstants.cardPadding),
    this.margin,
    this.onTap,
    this.backgroundColor,
    this.radius = AppConstants.cardRadius,
    this.showBorder = true,
    this.showShadow = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final Color? backgroundColor;
  final double radius;
  final bool showBorder;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: backgroundColor ?? brand.surface,
        borderRadius: BorderRadius.circular(radius),
        border: showBorder ? Border.all(color: brand.border) : null,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: brand.shadow,
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: child,
    );

    if (onTap == null) return card;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        splashColor: brand.accent.withValues(alpha: 0.08),
        highlightColor: brand.accent.withValues(alpha: 0.04),
        child: card,
      ),
    );
  }
}
