import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/brand_theme.dart';
import '../../features/notifications/presentation/notifications_drawer.dart';
import 'agent_activity_banner.dart';
import 'app_bottom_nav.dart';

/// Wraps the three bottom-nav branches (Home, Agent, Profile) so the nav
/// stays mounted while the body swaps.
class AppShellScaffold extends ConsumerWidget {
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
      initialLocation: targetIndex == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final activeTab = _indexToTab[navigationShell.currentIndex];
    final drawerOpen = ref.watch(notificationsDrawerOpenProvider);

    const scrimHeight =
        AppConstants.bottomNavHeight + AppConstants.bottomNavInset + 56;
    const slideDuration = Duration(milliseconds: 260);
    const slideCurve = Curves.easeOutCubic;
    final slideOffset = drawerOpen ? const Offset(0, 1.4) : Offset.zero;

    return Scaffold(
      backgroundColor: brand.bg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: navigationShell),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: scrimHeight,
            child: IgnorePointer(
              child: AnimatedSlide(
                duration: slideDuration,
                curve: slideCurve,
                offset: slideOffset,
                child: AnimatedOpacity(
                  duration: slideDuration,
                  curve: slideCurve,
                  opacity: drawerOpen ? 0 : 1,
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
                                brand.bg.withValues(alpha: 0.0),
                                brand.bg.withValues(alpha: 0.6),
                              ],
                            ),
                          ),
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
            child: IgnorePointer(
              ignoring: drawerOpen,
              child: AnimatedSlide(
                duration: slideDuration,
                curve: slideCurve,
                offset: slideOffset,
                child: AnimatedOpacity(
                  duration: slideDuration,
                  curve: slideCurve,
                  opacity: drawerOpen ? 0 : 1,
                  child: AppBottomNav(
                    activeTab: activeTab,
                    onTap: _onTabSelected,
                  ),
                ),
              ),
            ),
          ),
          // Global top banner: floats above every nav branch so agent
          // intercepts surface no matter which tab the user is on.
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AgentActivityBanner(),
          ),
        ],
      ),
    );
  }
}
