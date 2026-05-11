import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/router/route_names.dart';

enum BottomNavTab { home, agent, profile }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.activeTab});

  final BottomNavTab activeTab;

  @override
  Widget build(BuildContext context) {
    final items = <_BottomNavItem>[
      const _BottomNavItem(
        tab: BottomNavTab.home,
        label: 'Home',
        icon: Icons.home_rounded,
        outlineIcon: Icons.home_outlined,
        route: RouteNames.dashboard,
      ),
      const _BottomNavItem(
        tab: BottomNavTab.agent,
        label: 'Agent',
        icon: Icons.work_rounded,
        outlineIcon: Icons.work_outline_rounded,
        route: RouteNames.jobs,
      ),
      const _BottomNavItem(
        tab: BottomNavTab.profile,
        label: 'Profile',
        icon: Icons.account_circle_rounded,
        outlineIcon: Icons.account_circle_outlined,
        route: RouteNames.profile,
      ),
    ];

    return Container(
      height: AppConstants.bottomNavHeight,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.navBackground,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: items.map((item) {
          final isActive = activeTab == item.tab;
          return Expanded(
            child: Center(
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(28),
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => context.go(item.route),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 340),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isActive ? item.icon : item.outlineIcon,
                          size: 22,
                          color: isActive ? AppColors.ink : AppColors.navInactive,
                        ),
                        ClipRect(
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 340),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.centerLeft,
                            widthFactor: isActive ? 1 : 0,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 260),
                              curve: Curves.easeOut,
                              opacity: isActive ? 1 : 0,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Text(
                                  item.label,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BottomNavItem {
  const _BottomNavItem({
    required this.tab,
    required this.label,
    required this.icon,
    required this.outlineIcon,
    required this.route,
  });

  final BottomNavTab tab;
  final String label;
  final IconData icon;
  final IconData outlineIcon;
  final String route;
}
