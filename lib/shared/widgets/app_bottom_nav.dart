import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_colors.dart';
import '../../core/router/route_names.dart';

enum BottomNavTab { home, agent, profile }

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.activeTab, this.onTap});

  final BottomNavTab activeTab;

  /// When provided, called instead of routing via [GoRouter.go]. The shell
  /// scaffold uses this so taps go through [StatefulNavigationShell.goBranch]
  /// and preserve each branch's state.
  final ValueChanged<BottomNavTab>? onTap;

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

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _items.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          _NavPill(
            item: _items[i],
            isActive: activeTab == _items[i].tab,
            onTap: () {
              final cb = onTap;
              if (cb != null) {
                cb(_items[i].tab);
              } else {
                context.go(_items[i].route);
              }
            },
          ),
        ],
      ],
    );
  }
}

class _NavPill extends StatefulWidget {
  const _NavPill({
    required this.item,
    required this.isActive,
    required this.onTap,
  });

  final _BottomNavItem item;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_NavPill> createState() => _NavPillState();
}

class _NavPillState extends State<_NavPill>
    with SingleTickerProviderStateMixin {
  // One master duration/curve for every secondary animation on tap.
  static const Duration _shapeDuration = Duration(milliseconds: 320);
  static const Curve _shapeCurve = Curves.easeOutCubic;

  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  // Measured width of the inner pill; drives the sibling-push translation
  // so it tracks the pill's real size instead of a magic constant.
  final GlobalKey _pillKey = GlobalKey();
  double _pillWidth = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    // Continuous squash-and-settle: peak at 1.06, no mid-sequence jump.
    _pulse = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 1.0,
          end: 1.06,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.06,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
      ),
    ]).animate(_pulseController);
  }

  void _measurePill() {
    final box = _pillKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final w = box.size.width;
    if ((w - _pillWidth).abs() > 0.5) {
      setState(() => _pillWidth = w);
    }
  }

  @override
  void didUpdateWidget(covariant _NavPill oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only pulse when this pill becomes active — never on deactivation.
    if (widget.isActive && !oldWidget.isActive) {
      _pulseController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.selectionClick();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = AppColors.accentBright;
    final isActive = widget.isActive;
    final item = widget.item;

    // Re-measure after each layout so _pillWidth tracks the real pill width
    // (including the label expansion when isActive flips).
    WidgetsBinding.instance.addPostFrameCallback((_) => _measurePill());

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final scale = _pulse.value;
        // Push siblings outward by exactly the amount the scaled pill grew
        // on each side, so neighbours track the pill instead of over- or
        // under-shooting against a magic constant.
        final pushPx = (scale - 1.0) * _pillWidth / 2;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: pushPx),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Material(
        key: _pillKey,
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(31),
        shadowColor: Colors.black.withValues(alpha: 0.32),
        elevation: 8,
        child: InkWell(
          borderRadius: BorderRadius.circular(31),
          onTap: _handleTap,
          child: AnimatedContainer(
            duration: _shapeDuration,
            curve: _shapeCurve,
            height: 62,
            padding: EdgeInsets.symmetric(horizontal: isActive ? 22 : 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: _shapeDuration,
                  switchInCurve: _shapeCurve,
                  switchOutCurve: _shapeCurve,
                  child: Icon(
                    isActive ? item.icon : item.outlineIcon,
                    key: ValueKey<bool>(isActive),
                    size: 26,
                    color: isActive ? activeColor : AppColors.surface,
                  ),
                ),
                ClipRect(
                  child: AnimatedAlign(
                    duration: _shapeDuration,
                    curve: _shapeCurve,
                    alignment: Alignment.centerLeft,
                    widthFactor: isActive ? 1 : 0,
                    child: AnimatedOpacity(
                      duration: _shapeDuration,
                      curve: _shapeCurve,
                      opacity: isActive ? 1 : 0,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          item.label,
                          style: TextStyle(
                            color: activeColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.1,
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
