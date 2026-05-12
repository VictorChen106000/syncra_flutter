import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';
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
      extendBehindBottomNav: true,
      child: Column(
        children: [
          AppHeader.tab(title: AppStrings.profileTitle),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.screenHorizontalPadding,
                20,
                AppConstants.screenHorizontalPadding,
                140,
              ),
              children: const [
                _ProfileHeaderCard(),
                SizedBox(height: 24),
                SectionTitle(title: AppStrings.agentAutonomy),
                _AutonomySection(),
                SizedBox(height: 24),
                SectionTitle(title: AppStrings.careerPipeline),
                _CareerPipelineSection(),
                SizedBox(height: 24),
                SectionTitle(title: AppStrings.agentPermissions),
                _IntegrationSection(),
                SizedBox(height: 24),
                SectionTitle(title: AppStrings.preferences),
                _PreferenceSection(),
                SizedBox(height: 24),
                _SignOutButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header card
// ---------------------------------------------------------------------------

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        final user = auth.appUser;
        final displayName = user?.displayName ?? 'Daryn';
        final initial = user?.initial ?? 'D';
        final email = user?.email ?? '';
        final photoUrl = user?.photoUrl;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              _ProfileAvatar(
                photoUrl: photoUrl,
                initial: initial,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                        color: AppColors.ink,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    const Row(
                      children: [
                        _PulsingActiveDot(),
                        SizedBox(width: 8),
                        Text(
                          'Agent Active',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
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
      },
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.photoUrl, required this.initial});

  final String? photoUrl;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final hasNetworkPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    final ImageProvider image = hasNetworkPhoto
        ? NetworkImage(photoUrl!)
        : const AssetImage(AppAssets.profileImage);

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.ink,
        shape: BoxShape.circle,
        image: DecorationImage(
          image: image,
          fit: BoxFit.cover,
          onError: (_, _) {},
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.transparent,
          fontWeight: FontWeight.w900,
          fontSize: 22,
        ),
      ),
    );
  }
}

class _PulsingActiveDot extends StatelessWidget {
  const _PulsingActiveDot();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 10,
      height: 10,
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
                begin: const Offset(0.5, 0.5),
                end: const Offset(1.6, 1.6),
                curve: Curves.easeOut,
              )
              .fadeOut(duration: 1300.ms),
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppColors.accentBright,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Agent autonomy — three-position selector
// ---------------------------------------------------------------------------

class _AutonomySection extends StatefulWidget {
  const _AutonomySection();

  @override
  State<_AutonomySection> createState() => _AutonomySectionState();
}

class _AutonomySectionState extends State<_AutonomySection> {
  int _level = 1; // default to Ask First

  static const _options = [
    (AppStrings.autonomySuggest, AppStrings.autonomySuggestBody, Icons.lightbulb_outline_rounded),
    (AppStrings.autonomyAskFirst, AppStrings.autonomyAskFirstBody, Icons.front_hand_outlined),
    (AppStrings.autonomyAutoApply, AppStrings.autonomyAutoApplyBody, Icons.bolt_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final body = _options[_level].$2;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.border.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: List.generate(_options.length, (i) {
                final active = i == _level;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _level = i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: active ? AppColors.ink : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _options[i].$3,
                            size: 14,
                            color: active ? AppColors.accent : AppColors.textMuted,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _options[i].$1,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: active ? Colors.white : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              body,
              key: ValueKey(_level),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 12.5,
                height: 1.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
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
        return _GroupedCard(
          children: [
            _SettingsTile(
              icon: Icons.description_rounded,
              iconActive: true,
              title: 'Resumes',
              count: controller.resumes.length + controller.tailoredResumes.length,
              onTap: () => context.go(RouteNames.resumes),
            ),
            const _GroupedDivider(),
            _SettingsTile(
              icon: Icons.timeline_rounded,
              iconActive: true,
              title: 'Application Tracker',
              count: 5,
              onTap: () => context.go(RouteNames.tracker),
            ),
            const _GroupedDivider(),
            _SettingsTile(
              icon: Icons.search_rounded,
              iconActive: true,
              title: 'Discovered Roles',
              count: 4,
              onTap: () => context.go(RouteNames.jobs),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Integration section
// ---------------------------------------------------------------------------

class _IntegrationSection extends StatefulWidget {
  const _IntegrationSection();

  @override
  State<_IntegrationSection> createState() => _IntegrationSectionState();
}

class _IntegrationSectionState extends State<_IntegrationSection> {
  List<_Integration> _integrations = [
    const _Integration(
      icon: Icons.mail_outline_rounded,
      title: 'Gmail Workspace',
      subtitle: 'Allow Agent to draft outreach and parse rejections',
      active: true,
    ),
    const _Integration(
      icon: Icons.business_center_outlined,
      title: 'LinkedIn Data',
      subtitle: 'Keep AI Profile automatically synced',
      active: true,
    ),
    const _Integration(
      icon: Icons.draw_outlined,
      title: 'Portfolio Access',
      subtitle: 'Allow Agent to pull context from your projects',
      active: false,
    ),
  ];

  void _toggle(int i) {
    setState(() {
      _integrations = List.of(_integrations);
      _integrations[i] = _integrations[i].copyWith(active: !_integrations[i].active);
    });
  }

  @override
  Widget build(BuildContext context) {
    return _GroupedCard(
      children: [
        for (var i = 0; i < _integrations.length; i++) ...[
          _IntegrationTile(
            integration: _integrations[i],
            onToggle: () => _toggle(i),
          ),
          if (i < _integrations.length - 1) const _GroupedDivider(),
        ],
      ],
    );
  }
}

class _IntegrationTile extends StatelessWidget {
  const _IntegrationTile({required this.integration, required this.onToggle});

  final _Integration integration;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: integration.active ? AppColors.accent : AppColors.scaffold,
              borderRadius: BorderRadius.circular(12),
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
                const SizedBox(height: 3),
                Text(
                  integration.subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onToggle,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              width: 44,
              height: 24,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: integration.active ? AppColors.ink : AppColors.border,
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                alignment: integration.active
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
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

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------

class _PreferenceSection extends StatelessWidget {
  const _PreferenceSection();

  @override
  Widget build(BuildContext context) {
    return const _GroupedCard(
      children: [
        _SettingsTile(
          icon: Icons.notifications_none_rounded,
          title: 'Agent Notifications',
        ),
        _GroupedDivider(),
        _SettingsTile(
          icon: Icons.shield_outlined,
          title: 'Privacy & Data',
        ),
        _GroupedDivider(),
        _SettingsTile(
          icon: Icons.palette_outlined,
          title: 'Appearance',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Settings tile
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconActive ? AppColors.ink : AppColors.scaffold,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: iconActive ? Colors.white : AppColors.ink,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: AppColors.ink,
                  ),
                ),
              ),
              if (count != null) ...[
                Text(
                  '$count',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.border,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grouped card container — eliminates per-row borders / shadows
// ---------------------------------------------------------------------------

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _GroupedDivider extends StatelessWidget {
  const _GroupedDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 64),
      child: Divider(height: 1, color: AppColors.scaffold),
    );
  }
}

// ---------------------------------------------------------------------------
// Sign out button
// ---------------------------------------------------------------------------

class _SignOutButton extends StatelessWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        final loading = auth.isLoading;
        return Material(
          color: AppColors.scaffold,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: loading ? null : () => auth.signOut(),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout_rounded, size: 16, color: AppColors.ink),
                  const SizedBox(width: 8),
                  Text(
                    loading ? 'Signing out...' : AppStrings.signOut,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
