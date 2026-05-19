import 'package:flutter/material.dart';

import '../../core/theme/brand_theme.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, this.onTap, this.showDot = true});

  final VoidCallback? onTap;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Semantics(
      label: showDot ? 'Notifications, unread' : 'Notifications',
      button: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        excludeFromSemantics: true,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: brand.surface,
                  border: Border.all(color: brand.border),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_none_rounded,
                  size: 21,
                  color: brand.ink,
                ),
              ),
              if (showDot)
                Positioned(
                  right: 8,
                  top: 7,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: brand.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: brand.surface, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
