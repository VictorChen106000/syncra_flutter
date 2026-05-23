import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/brand_theme.dart';

/// Translucent + blurred surface for floating chrome that should let the
/// transcript stay faintly visible behind it. The shadow is the only structure
/// — no second border — so it reads as glass, not as a card.
class FrostedCard extends StatelessWidget {
  const FrostedCard({super.key, required this.child, this.radius = 16});

  final Widget child;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            color: brand.shadow.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: brand.surface.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(color: brand.border, width: 0.8),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Frosted circular icon button — the floating header pattern.
class FrostedIconButton extends StatelessWidget {
  const FrostedIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final enabled = onTap != null;
    final button = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: brand.shadow.withValues(alpha: 0.12),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Material(
            color: brand.surface.withValues(alpha: 0.78),
            shape: CircleBorder(
              side: BorderSide(color: brand.border, width: 0.8),
            ),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  icon,
                  size: 18,
                  color: enabled ? brand.ink : brand.textSoft,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
