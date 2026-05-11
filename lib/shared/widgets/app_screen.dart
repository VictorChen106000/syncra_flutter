import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import 'app_bottom_nav.dart';

class AppScreen extends StatelessWidget {
  const AppScreen({
    super.key,
    required this.child,
    this.showBottomNav = false,
    this.activeTab = BottomNavTab.home,
    this.extendBehindBottomNav = false,
    this.backgroundColor = AppColors.scaffold,
  });

  final Widget child;
  final bool showBottomNav;
  final BottomNavTab activeTab;
  final bool extendBehindBottomNav;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: showBottomNav && !extendBehindBottomNav
                      ? AppConstants.bottomNavHeight + AppConstants.bottomNavInset + 16
                      : 0,
                ),
                child: child,
              ),
            ),
            if (showBottomNav)
              Positioned(
                left: AppConstants.screenHorizontalPadding,
                right: AppConstants.screenHorizontalPadding,
                bottom: AppConstants.bottomNavInset,
                child: AppBottomNav(activeTab: activeTab),
              ),
          ],
        ),
      ),
    );
  }
}
