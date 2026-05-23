import 'package:flutter/material.dart';

import '../../core/theme/brand_theme.dart';

/// Ink-filled CTA used in modal sheets and confirmation flows — distinct from
/// the lime [AppPrimaryButton], which is the global brand CTA. Use this when
/// the action is *decisive* (Send, Save, Delete) rather than promotional.
enum InkButtonVariant { filled, outlined, destructive }

class InkButton extends StatelessWidget {
  const InkButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.variant = InkButtonVariant.filled,
    this.busy = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final InkButtonVariant variant;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isOutlined = variant == InkButtonVariant.outlined;
    final bg = switch (variant) {
      InkButtonVariant.filled => brand.ink,
      InkButtonVariant.destructive => brand.danger,
      InkButtonVariant.outlined => brand.surface,
    };
    final fg = isOutlined ? brand.ink : brand.inkInverse;
    final disabled = onTap == null && !busy;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(99),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: isOutlined ? brand.border : Colors.transparent,
              ),
            ),
            child: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(fg),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 16, color: fg),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: fg,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
