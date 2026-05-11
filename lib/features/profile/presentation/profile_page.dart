import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../../shared/widgets/notification_bell.dart';
import '../../../shared/widgets/section_title.dart';
import '../../resumes/state/resume_controller.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      showBottomNav: true,
      activeTab: BottomNavTab.profile,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        children: [
          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.profileTitle,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              const NotificationBell(),
            ],
          ),
          const SizedBox(height: 22),
          const _ProfileHeaderCard(),
          const SizedBox(height: 26),
          const SectionTitle(title: AppStrings.careerPipeline),
          const _CareerPipelineSection(),
          const SizedBox(height: 24),
          const SectionTitle(title: AppStrings.agentPermissions),
          const _IntegrationSection(),
          const SizedBox(height: 24),
          const SectionTitle(title: AppStrings.preferences),
          const _PreferenceSection(),
          const SizedBox(height: 24),
          // Sign out button
          Material(
            color: AppColors.scaffold,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: () => context.go(RouteNames.login),
              borderRadius: BorderRadius.circular(18),
              hoverColor: Colors.red.shade50,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.logout_rounded, size: 18, color: AppColors.ink),
                    SizedBox(width: 8),
                    Text(
                      'Sign Out',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.ink,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile header card with pulsing "Agent Active" dot
// ---------------------------------------------------------------------------

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.ink,
            child: const Text(
              'D',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daryn',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 5),
                Row(
                  children: [
                    _PulsingActiveDot(),
                    SizedBox(width: 7),
                    Text(
                      'Agent Active',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pulsing green dot (Agent Active indicator)
// ---------------------------------------------------------------------------

class _PulsingActiveDot extends StatefulWidget {
  const _PulsingActiveDot();

  @override
  State<_PulsingActiveDot> createState() => _PulsingActiveDotState();
}

class _PulsingActiveDotState extends State<_PulsingActiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.accent.withValues(alpha: _opacity.value),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Career pipeline section
// ---------------------------------------------------------------------------

class _CareerPipelineSection extends StatelessWidget {
  const _CareerPipelineSection();

  @override
  Widget build(BuildContext context) {
    return Consumer<ResumeController>(
      builder: (context, controller, _) {
        return AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _SettingsTile(
                icon: Icons.description_rounded,
                iconActive: true,
                title: 'Resume Lists',
                count: controller.resumes.length + controller.tailoredResumes.length,
                onTap: () => context.go(RouteNames.resumes),
              ),
              const Divider(height: 1, indent: 60, color: AppColors.scaffold),
              const _SettingsTile(
                icon: Icons.search_rounded,
                iconActive: true,
                title: 'Discovered Roles',
                count: 4,
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Integration section — stateful so toggles actually work
// ---------------------------------------------------------------------------

class _IntegrationSection extends StatefulWidget {
  const _IntegrationSection();

  @override
  State<_IntegrationSection> createState() => _IntegrationSectionState();
}

class _IntegrationSectionState extends State<_IntegrationSection> {
  final List<_Integration> _integrations = [
    _Integration(
      icon: Icons.mail_outline_rounded,
      title: 'Gmail Workspace',
      subtitle: 'Allow Agent to draft outreach and parse rejections',
      active: true,
    ),
    _Integration(
      icon: Icons.business_center_rounded,
      title: 'LinkedIn Data',
      subtitle: 'Keep AI Profile automatically synced',
      active: true,
    ),
    _Integration(
      icon: Icons.draw_rounded,
      title: 'Portfolio Access',
      subtitle: 'Allow Agent to pull context from your projects',
      active: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: List.generate(_integrations.length, (i) {
          final item = _integrations[i];
          return Column(
            children: [
              _IntegrationTile(
                integration: item,
                onToggle: () => setState(() => _integrations[i] = item.copyWith(active: !item.active)),
              ),
              if (i < _integrations.length - 1)
                const Divider(height: 1, indent: 60, color: AppColors.scaffold),
            ],
          );
        }),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preferences section
// ---------------------------------------------------------------------------

class _PreferenceSection extends StatelessWidget {
  const _PreferenceSection();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _SettingsTile(icon: Icons.notifications_none_rounded, title: 'Agent Notifications'),
          Divider(height: 1, indent: 60, color: AppColors.scaffold),
          _SettingsTile(icon: Icons.shield_outlined, title: 'Privacy & Data'),
          Divider(height: 1, indent: 60, color: AppColors.scaffold),
          _SettingsTile(icon: Icons.palette_outlined, title: 'Appearance'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable settings tile
// ---------------------------------------------------------------------------

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.iconActive = false,
    this.count,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final bool iconActive;
  final int? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count != null)
            Text(
              '$count',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppColors.border, size: 20),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Integration tile
// ---------------------------------------------------------------------------

class _IntegrationTile extends StatelessWidget {
  const _IntegrationTile({
    required this.integration,
    required this.onToggle,
  });

  final _Integration integration;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: integration.active ? AppColors.accent : AppColors.scaffold,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              integration.icon,
              color: integration.active ? AppColors.ink : AppColors.textSoft,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  integration.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  integration.subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 44,
              height: 24,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: integration.active ? AppColors.ink : AppColors.border,
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: integration.active
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Data class for integration items
// ---------------------------------------------------------------------------

class _Integration {
  const _Integration({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;

  _Integration copyWith({bool? active}) => _Integration(
        icon: icon,
        title: title,
        subtitle: subtitle,
        active: active ?? this.active,
      );
}
