import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';

class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.border),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.notifications_none_rounded, size: 21),
        ),
        Positioned(
          right: 9,
          top: 8,
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: AppColors.danger,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }
}
