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
  });

  final Widget child;
  final bool showBottomNav;
  final BottomNavTab activeTab;
  final bool extendBehindBottomNav;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: showBottomNav && !extendBehindBottomNav ? 104 : 0,
                ),
                child: child,
              ),
            ),
            if (showBottomNav)
              Positioned(
                left: AppConstants.screenHorizontalPadding,
                right: AppConstants.screenHorizontalPadding,
                bottom: 24,
                child: AppBottomNav(activeTab: activeTab),
              ),
          ],
        ),
      ),
    );
  }
}
