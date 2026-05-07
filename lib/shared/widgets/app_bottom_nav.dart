import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/router/route_names.dart';

enum BottomNavTab { home, agent, profile }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.activeTab});

  final BottomNavTab activeTab;

  @override
  Widget build(BuildContext context) {
    final items = [
      _BottomNavItem(
        tab: BottomNavTab.home,
        label: 'Home',
        icon: Icons.home_rounded,
        route: RouteNames.dashboard,
      ),
      _BottomNavItem(
        tab: BottomNavTab.agent,
        label: 'Agent',
        icon: Icons.auto_awesome_rounded,
        route: RouteNames.agentChat,
      ),
      _BottomNavItem(
        tab: BottomNavTab.profile,
        label: 'Profile',
        icon: Icons.person_rounded,
        route: RouteNames.profile,
      ),
    ];

    return Container(
      height: 68,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.navBackground,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity( 0.20),
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
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: isActive ? AppColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: AppColors.accent.withOpacity( 0.40),
                            blurRadius: 12,
                          ),
                        ]
                      : null,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(28),
                  onTap: () => context.go(item.route),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isActive ? 18 : 14,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          item.icon,
                          size: 24,
                          color: isActive ? AppColors.ink : AppColors.navInactive,
                        ),
                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: isActive
                              ? Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Text(
                                    item.label,
                                    style: const TextStyle(
                                      color: AppColors.ink,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
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
    required this.route,
  });

  final BottomNavTab tab;
  final String label;
  final IconData icon;
  final String route;
}
