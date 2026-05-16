import 'dart:ui';

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

    // Height of the blurred fade region behind the floating nav. Tall enough
    // that scrolled content softens before reaching the pills.
    const scrimHeight =
        AppConstants.bottomNavHeight + AppConstants.bottomNavInset + 56;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: Stack(
        children: [
          Positioned.fill(child: navigationShell),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: scrimHeight,
            child: IgnorePointer(
              child: ClipRect(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (rect) {
                    return const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                      stops: [0.0, 0.55],
                    ).createShader(rect);
                  },
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            AppColors.scaffold.withValues(alpha: 0.0),
                            AppColors.scaffold.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
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
