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
import '../../auth/state/auth_controller.dart';
import '../../resumes/state/resume_controller.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      showBottomNav: true,
      activeTab: BottomNavTab.profile,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        children: [
          Row(
            children: [
              Expanded(child: Text(AppStrings.profileTitle, style: Theme.of(context).textTheme.headlineMedium)),
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
          Consumer<AuthController>(
            builder: (context, authController, _) {
              return TextButton.icon(
                onPressed: authController.isLoading
                    ? null
                    : () => authController.signOut(),
                icon: const Icon(Icons.logout_rounded),
                label: Text(authController.isLoading ? 'Signing out...' : 'Sign Out'),
                style: TextButton.styleFrom(foregroundColor: AppColors.ink),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, authController, _) {
        final user = authController.appUser;
        final displayName = user?.displayName ?? 'User';
        final initial = user?.initial ?? 'U';
        final email = user?.email ?? '';

        return AppCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.ink,
                child: Text(initial, style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900, fontSize: 20)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(displayName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(email, style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                    const SizedBox(height: 4),
                    const Row(
                      children: [
                        CircleAvatar(radius: 4, backgroundColor: AppColors.accent),
                        SizedBox(width: 7),
                        Text('Agent Active', style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

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
                title: 'Resume Lists',
                count: controller.resumes.length + controller.tailoredResumes.length,
                onTap: () => context.go(RouteNames.resumes),
              ),
              const Divider(height: 1, indent: 60, color: AppColors.scaffold),
              _SettingsTile(
                icon: Icons.search_rounded,
                title: 'Discovered Roles',
                count: 4,
                onTap: () {},
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IntegrationSection extends StatelessWidget {
  const _IntegrationSection();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          _IntegrationTile(icon: Icons.mail_outline_rounded, title: 'Gmail Workspace', subtitle: 'Allow Agent to draft outreach and parse rejections', active: true),
          Divider(height: 1, indent: 60, color: AppColors.scaffold),
          _IntegrationTile(icon: Icons.business_center_rounded, title: 'LinkedIn Data', subtitle: 'Keep AI Profile automatically synced', active: true),
          Divider(height: 1, indent: 60, color: AppColors.scaffold),
          _IntegrationTile(icon: Icons.draw_rounded, title: 'Portfolio Access', subtitle: 'Allow Agent to pull context from your projects', active: false),
        ],
      ),
    );
  }
}

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

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.count,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final int? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppColors.ink,
        child: Icon(icon, color: Colors.white, size: 19),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count != null)
            Text('$count', style: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w800)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: AppColors.border),
        ],
      ),
    );
  }
}

class _IntegrationTile extends StatelessWidget {
  const _IntegrationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: active ? AppColors.accent : AppColors.scaffold,
        child: Icon(icon, color: active ? AppColors.ink : AppColors.textSoft, size: 19),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
      trailing: Switch(
        value: active,
        onChanged: (_) {},
        activeColor: AppColors.accent,
        activeTrackColor: AppColors.ink,
      ),
    );
  }
}
