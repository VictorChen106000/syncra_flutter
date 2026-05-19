import 'package:flutter/material.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/brand_theme.dart';
import 'app_bottom_nav.dart';

class AppScreen extends StatelessWidget {
  const AppScreen({
    super.key,
    required this.child,
    this.showBottomNav = false,
    this.activeTab = BottomNavTab.home,
    this.extendBehindBottomNav = false,
    this.backgroundColor,
    this.drawer,
    this.drawerEdgeDragWidth,
    this.onDrawerChanged,
  });

  final Widget child;
  final bool showBottomNav;
  final BottomNavTab activeTab;
  final bool extendBehindBottomNav;
  final Color? backgroundColor;

  /// Optional slide-in panel from the left edge.
  final Widget? drawer;

  /// Width of the left-edge swipe-to-open area. Defaults to Flutter's
  /// 20pt — widen it to make the gesture more discoverable.
  final double? drawerEdgeDragWidth;

  /// Fires `true` when the drawer starts opening and `false` when it
  /// finishes closing. Used by the shell to hide the floating bottom nav
  /// while the drawer is on screen.
  final ValueChanged<bool>? onDrawerChanged;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Scaffold(
      backgroundColor: backgroundColor ?? brand.bg,
      drawer: drawer,
      drawerEdgeDragWidth: drawerEdgeDragWidth,
      onDrawerChanged: onDrawerChanged,
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
