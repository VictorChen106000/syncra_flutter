import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/dev/dev_flags_notifier.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../core/theme/theme_mode_notifier.dart';
import '../../../core/utils/motion.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../../shared/widgets/section_title.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/state/auth_notifier.dart';
import '../../auth/state/user_profile_notifier.dart';
import '../../resumes/state/resume_notifier.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      showBottomNav: false,
      activeTab: BottomNavTab.profile,
      extendBehindBottomNav: true,
      child: Column(
        children: [
          AppHeader.tab(title: AppStrings.profileTitle),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppConstants.screenHorizontalPadding,
                16,
                AppConstants.screenHorizontalPadding,
                140,
              ),
              children: [
                const _ProfileHeaderCard(),
                const SizedBox(height: 24),
                const SectionTitle(title: AppStrings.careerPipeline),
                const _CareerPipelineSection(),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Connections'),
                const _IntegrationSection(),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Preferences'),
                const _PreferencesSection(),
                if (kDebugMode) ...const [
                  SizedBox(height: 24),
                  SectionTitle(title: 'Developer'),
                  _DevFlagsSection(),
                ],
                const SizedBox(height: 24),
                const _SignOutButton(),
                const SizedBox(height: 12),
                const _DeleteAccountButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preferences — a single grouped card with three compact tiles:
// Dark mode · Today's brief · Agent autonomy.
// ---------------------------------------------------------------------------

class _PreferencesSection extends StatelessWidget {
  const _PreferencesSection();

  @override
  Widget build(BuildContext context) {
    return const _GroupedCard(
      children: [
        _ThemeModeTile(),
        _GroupedDivider(),
        _MorningBriefTile(),
        _GroupedDivider(),
        _AutonomyTile(),
      ],
    );
  }
}

/// Standard row layout used by every preference tile.
/// Icon · title (+ optional subtitle) · trailing control.
class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: brand.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: brand.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: brand.ink,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: brand.textMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// Tiny icon-only segmented selector — three choices in a single pill.
/// Active option flips to ink background with accent-colored icon.
class _MiniSegmented<T> extends StatelessWidget {
  const _MiniSegmented({
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<(T, IconData)> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: brand.surfaceMuted,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (value, icon) in options)
            GestureDetector(
              onTap: () => onChanged(value),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 30,
                height: 28,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: value == selected ? brand.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 14,
                  color: value == selected ? brand.accent : brand.textMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileHeaderCard extends ConsumerWidget {
  const _ProfileHeaderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final user = ref.watch(authProvider).appUser;
    final displayName = user?.displayName ?? 'there';
    final initial = user?.initial ?? 'D';
    final email = user?.email ?? '';
    final photoUrl = user?.photoUrl;

    return Container(
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: brand.border),
        boxShadow: [
          BoxShadow(
            color: brand.shadow,
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          _ProfileAvatar(photoUrl: photoUrl, initial: initial),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    height: 1.2,
                    color: brand.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    email,
                    style: TextStyle(
                      color: brand.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    const _PulsingActiveDot(),
                    const SizedBox(width: 8),
                    Text(
                      'Agent Active',
                      style: TextStyle(
                        color: brand.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1,
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

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.photoUrl, required this.initial});

  final String? photoUrl;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hasNetworkPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    final ImageProvider image = hasNetworkPhoto
        ? NetworkImage(photoUrl!)
        : const AssetImage(AppAssets.profileImage);

    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: brand.ink,
        shape: BoxShape.circle,
      ),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: brand.accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            ),
            Image(
              image: image,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingActiveDot extends StatelessWidget {
  const _PulsingActiveDot();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SizedBox(
      width: 10,
      height: 10,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: brand.accent.withValues(alpha: 0.45),
            ),
          )
              .animate(onPlay: repeatIfMotion(context))
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
            decoration: BoxDecoration(
              color: brand.accentBright,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeTile extends ConsumerWidget {
  const _ThemeModeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(themeModeProvider);
    final subtitle = switch (selected) {
      ThemeMode.light => 'Always light',
      ThemeMode.dark => 'Always dark',
      ThemeMode.system => 'Match device',
    };
    return _PreferenceRow(
      icon: Icons.contrast_rounded,
      title: 'Appearance',
      subtitle: subtitle,
      trailing: _MiniSegmented<ThemeMode>(
        selected: selected,
        onChanged: (m) =>
            ref.read(themeModeProvider.notifier).setMode(m),
        options: const [
          (ThemeMode.light, Icons.wb_sunny_outlined),
          (ThemeMode.dark, Icons.dark_mode_outlined),
          (ThemeMode.system, Icons.brightness_auto_outlined),
        ],
      ),
    );
  }
}

class _MorningBriefTile extends ConsumerWidget {
  const _MorningBriefTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final profile = ref.watch(userProfileProvider);
    final enabled = profile?.morningBriefEnabled ?? false;
    return _PreferenceRow(
      icon: Icons.wb_sunny_outlined,
      title: "Today's brief",
      subtitle: enabled ? 'Dashboard CTA on' : 'Dashboard CTA off',
      trailing: Switch.adaptive(
        value: enabled,
        activeThumbColor: brand.ink,
        onChanged: profile == null
            ? null
            : (v) => ref
                .read(userProfileProvider.notifier)
                .setMorningBriefEnabled(v),
      ),
    );
  }
}

class _AutonomyTile extends ConsumerWidget {
  const _AutonomyTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final selected = profile?.autonomyLevel ?? AutonomyLevel.askFirst;
    final subtitle = switch (selected) {
      AutonomyLevel.suggest => 'Only suggest',
      AutonomyLevel.askFirst => 'Ask before acting',
      AutonomyLevel.autoApply => 'Auto-apply',
    };
    return _PreferenceRow(
      icon: Icons.bolt_rounded,
      title: 'Agent autonomy',
      subtitle: subtitle,
      trailing: _MiniSegmented<AutonomyLevel>(
        selected: selected,
        onChanged: (l) =>
            ref.read(userProfileProvider.notifier).setAutonomyLevel(l),
        options: const [
          (AutonomyLevel.suggest, Icons.lightbulb_outline_rounded),
          (AutonomyLevel.askFirst, Icons.front_hand_outlined),
          (AutonomyLevel.autoApply, Icons.bolt_rounded),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Developer toggles — only rendered when `kDebugMode == true`, so they're
// stripped from release builds. Used to skip onboarding / morning brief and
// to force the notification bell's unread dot while iterating on UI.
// ---------------------------------------------------------------------------

class _DevFlagsSection extends ConsumerWidget {
  const _DevFlagsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(devFlagsProvider);
    final notifier = ref.read(devFlagsProvider.notifier);
    final brand = context.brand;
    return _GroupedCard(
      children: [
        _PreferenceRow(
          icon: Icons.flag_outlined,
          title: 'Skip onboarding',
          subtitle: 'Bypass the role-setup gate after sign-in',
          trailing: Switch.adaptive(
            value: flags.skipOnboarding,
            activeThumbColor: brand.ink,
            onChanged: notifier.setSkipOnboarding,
          ),
        ),
        const _GroupedDivider(),
        _PreferenceRow(
          icon: Icons.wb_twilight_outlined,
          title: 'Skip morning brief',
          subtitle: 'Land on dashboard, not the brief',
          trailing: Switch.adaptive(
            value: flags.skipMorningBrief,
            activeThumbColor: brand.ink,
            onChanged: notifier.setSkipMorningBrief,
          ),
        ),
        const _GroupedDivider(),
        _PreferenceRow(
          icon: Icons.notifications_active_outlined,
          title: 'Force notification dot',
          subtitle: 'Show unread indicator on the bell',
          trailing: Switch.adaptive(
            value: flags.forceNotificationDot,
            activeThumbColor: brand.ink,
            onChanged: notifier.setForceNotificationDot,
          ),
        ),
      ],
    );
  }
}

class _CareerPipelineSection extends ConsumerWidget {
  const _CareerPipelineSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(resumeProvider);
    return _GroupedCard(
      children: [
        _SettingsTile(
          icon: Icons.description_rounded,
          iconActive: true,
          title: 'Resumes',
          count: state.resumes.length + state.tailoredResumes.length,
          onTap: () => context.go(RouteNames.resumes),
        ),
        const _GroupedDivider(),
        _SettingsTile(
          icon: Icons.timeline_rounded,
          iconActive: true,
          title: 'Application Tracker',
          count: 5,
          onTap: () => context.go(RouteNames.applications),
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
  }
}

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
  ];

  void _toggle(int i) {
    setState(() {
      _integrations = List.of(_integrations);
      _integrations[i] =
          _integrations[i].copyWith(active: !_integrations[i].active);
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
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: integration.active ? brand.accent : brand.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              integration.icon,
              color: integration.active ? brand.onAccent : brand.textSoft,
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
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: brand.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  integration.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: brand.textMuted,
                    height: 1.45,
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
                color: integration.active ? brand.ink : brand.border,
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
                    color: brand.surface,
                    boxShadow: [
                      BoxShadow(
                        color: brand.shadow,
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

class _DeleteAccountButton extends ConsumerWidget {
  const _DeleteAccountButton();

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final brand = context.brand;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your Syncra profile and signs you out. '
          'Resumes saved on this device will remain until you uninstall the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: brand.danger),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(authProvider.notifier).deleteAccount();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final loading = ref.watch(authProvider).isLoading;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
      child: InkWell(
        onTap: loading ? null : () => _confirmAndDelete(context, ref),
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            border: Border.all(
              color: brand.danger.withValues(alpha: 0.30),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline_rounded, size: 14, color: brand.danger),
              const SizedBox(width: 8),
              Text(
                'Delete account',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: brand.danger,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    final brand = context.brand;
    final isTappable = onTap != null;
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
                  color: iconActive ? brand.ink : brand.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: iconActive ? brand.inkInverse : brand.ink,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: brand.ink,
                  ),
                ),
              ),
              if (count != null) ...[
                Text(
                  '$count',
                  style: TextStyle(
                    color: brand.textMuted,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (isTappable)
                Icon(
                  Icons.chevron_right_rounded,
                  color: brand.border,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: brand.border),
        boxShadow: [
          BoxShadow(
            color: brand.shadow,
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
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(left: 64),
      child: Divider(height: 1, color: brand.bg),
    );
  }
}

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final loading = ref.watch(authProvider).isLoading;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
      child: InkWell(
        onTap: loading
            ? null
            : () => ref.read(authProvider.notifier).signOut(),
        borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: brand.danger.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(AppConstants.buttonRadius),
            border: Border.all(
              color: brand.danger.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (loading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(brand.danger),
                  ),
                )
              else
                Icon(Icons.logout_rounded, size: 16, color: brand.danger),
              const SizedBox(width: 10),
              Text(
                loading ? 'Signing out…' : AppStrings.signOut,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: brand.danger,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
