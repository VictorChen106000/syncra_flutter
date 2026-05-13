import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/router/route_names.dart';

enum BottomNavTab { home, agent, profile }

class AppBottomNav extends StatefulWidget {
  const AppBottomNav({super.key, required this.activeTab, this.onTap});

  final BottomNavTab activeTab;

  /// When provided, called instead of routing via [GoRouter.go]. The shell
  /// scaffold uses this so taps go through [StatefulNavigationShell.goBranch]
  /// and preserve each branch's state.
  final ValueChanged<BottomNavTab>? onTap;

  @override
  State<AppBottomNav> createState() => _AppBottomNavState();
}

class _AppBottomNavState extends State<AppBottomNav> {
  // Demo flag: toggled by long-pressing the Agent tab.
  // Replace with real AgentController state when the stream lands.
  bool _agentWorking = false;
  String _agentStatus = 'Tailoring resume…';

  static const _items = <_BottomNavItem>[
    _BottomNavItem(
      tab: BottomNavTab.home,
      label: 'Home',
      icon: Icons.home_rounded,
      outlineIcon: Icons.home_outlined,
      route: RouteNames.dashboard,
    ),
    _BottomNavItem(
      tab: BottomNavTab.agent,
      label: 'Agent',
      icon: Icons.work_rounded,
      outlineIcon: Icons.work_outline_rounded,
      route: RouteNames.jobs,
    ),
    _BottomNavItem(
      tab: BottomNavTab.profile,
      label: 'Profile',
      icon: Icons.account_circle_rounded,
      outlineIcon: Icons.account_circle_outlined,
      route: RouteNames.profile,
    ),
  ];

  void _toggleAgentDemo() {
    setState(() {
      _agentWorking = !_agentWorking;
      _agentStatus = _agentWorking ? 'Tailoring resume…' : '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: AppColors.navBackground,
        borderRadius: BorderRadius.circular(34),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.22),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 420),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _agentWorking
                ? _AgentStatusStrip(status: _agentStatus)
                : const SizedBox(width: double.infinity, height: 0),
          ),
          SizedBox(
            height: AppConstants.bottomNavHeight - 16,
            child: Row(
              children: _items.map((item) {
                final isActive = widget.activeTab == item.tab;
                return Expanded(
                  child: Center(
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(28),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(28),
                        onTap: () {
                          final onTap = widget.onTap;
                          if (onTap != null) {
                            onTap(item.tab);
                          } else {
                            context.go(item.route);
                          }
                        },
                        onLongPress: item.tab == BottomNavTab.agent
                            ? _toggleAgentDemo
                            : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? AppColors.accent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 320),
                                switchInCurve: Curves.easeOutCubic,
                                switchOutCurve: Curves.easeInCubic,
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(begin: 0.78, end: 1)
                                          .animate(
                                            CurvedAnimation(
                                              parent: animation,
                                              curve: Curves.easeOutBack,
                                            ),
                                          ),
                                      child: child,
                                    ),
                                  );
                                },
                                child: Icon(
                                  isActive ? item.icon : item.outlineIcon,
                                  key: ValueKey<bool>(isActive),
                                  size: 22,
                                  color: isActive
                                      ? AppColors.ink
                                      : AppColors.navInactive,
                                ),
                              ),
                              ClipRect(
                                child: AnimatedAlign(
                                  duration: const Duration(milliseconds: 420),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.centerLeft,
                                  widthFactor: isActive ? 1 : 0,
                                  child: AnimatedSlide(
                                    duration: const Duration(milliseconds: 420),
                                    curve: Curves.easeOutCubic,
                                    offset: isActive
                                        ? Offset.zero
                                        : const Offset(-0.25, 0),
                                    child: AnimatedOpacity(
                                      duration: const Duration(
                                        milliseconds: 320,
                                      ),
                                      curve: Curves.easeOutCubic,
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
          ),
        ],
      ),
    );
  }
}

class _AgentStatusStrip extends StatelessWidget {
  const _AgentStatusStrip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Padding(
          padding: const EdgeInsets.only(left: 6, right: 6, top: 4, bottom: 10),
          child: Row(
            children: [
              const _PulsingDot(),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ],
          ),
        )
        .animate()
        .fadeIn(duration: 240.ms, curve: Curves.easeOut)
        .slideY(
          begin: -0.25,
          end: 0,
          duration: 320.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

class _PulsingDot extends StatelessWidget {
  const _PulsingDot();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: 12,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accent.withValues(alpha: 0.45),
                ),
              )
              .animate(onPlay: (c) => c.repeat())
              .scale(
                duration: 1300.ms,
                begin: const Offset(0.4, 0.4),
                end: const Offset(1.7, 1.7),
                curve: Curves.easeOut,
              )
              .fadeOut(duration: 1300.ms),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
        ],
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
