import 'package:flutter/material.dart';

import '../../core/theme/brand_theme.dart';

/// Small label chip used throughout — `4 Pending`, `Responsive design`, etc.
class StepPill extends StatelessWidget {
  const StepPill({
    super.key,
    required this.label,
    this.accent = false,
    this.color,
    this.textColor,
    this.icon,
  });

  final String label;
  final bool accent;
  final Color? color;
  final Color? textColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final background = color ?? (accent ? brand.accent : brand.surface);
    final foreground = textColor ?? (accent ? brand.onAccent : brand.ink);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(99),
        border: !accent && color == null
            ? Border.all(color: brand.border)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: foreground,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
