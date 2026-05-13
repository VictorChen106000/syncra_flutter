import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import 'app_bottom_nav.dart';

/// Wraps the three bottom-nav branches (Home, Agent, Profile) so the nav
/// stays mounted while the body swaps. This is what lets the nav animate
/// between tabs — without a shell route, the whole widget tree is torn
/// down on every navigation.
class AppShellScaffold extends StatelessWidget {
  const AppShellScaffold({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _indexToTab = [
    BottomNavTab.home,
    BottomNavTab.agent,
    BottomNavTab.profile,
  ];

  void _onTabSelected(BottomNavTab tab) {
    final targetIndex = _indexToTab.indexOf(tab);
    navigationShell.goBranch(
      targetIndex,
      // Tapping the already-active tab returns to that branch's initial route.
      initialLocation: targetIndex == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = _indexToTab[navigationShell.currentIndex];

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: Stack(
        children: [
          Positioned.fill(child: navigationShell),
          Positioned(
            left: AppConstants.screenHorizontalPadding,
            right: AppConstants.screenHorizontalPadding,
            bottom: AppConstants.bottomNavInset,
            child: AppBottomNav(
              activeTab: activeTab,
              onTap: _onTabSelected,
            ),
          ),
        ],
      ),
    );
  }
}
