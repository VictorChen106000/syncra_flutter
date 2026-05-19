import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/brand_theme.dart';

/// Translucent capsule pill used as floating headers across screens.
class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: brand.glassFill,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: brand.glassBorder),
            boxShadow: [
              BoxShadow(
                color: brand.shadow,
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Small round translucent icon button used in headers.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 40,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return InkResponse(
      onTap: onTap,
      radius: size / 2 + 4,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: brand.glassFill,
          shape: BoxShape.circle,
          border: Border.all(color: brand.glassBorder),
          boxShadow: [
            BoxShadow(
              color: brand.shadow,
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, color: brand.ink, size: size * 0.5),
      ),
    );
  }
}
