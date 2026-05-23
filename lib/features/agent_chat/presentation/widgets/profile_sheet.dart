import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_assets.dart';
import '../../../../core/constants/app_strings.dart';
import '../../../../core/dev/dev_flags_notifier.dart';
import '../../../../core/theme/brand_theme.dart';
import '../../../../core/theme/theme_mode_notifier.dart';
import '../../../../core/utils/motion.dart';
import '../../../agent/state/passive_agent_notifier.dart';
import '../../../auth/state/auth_notifier.dart';
import '../../../auth/state/user_profile_notifier.dart';
import '../../../resumes/state/resume_notifier.dart';

/// Full-height bottom sheet that holds the entire Settings UI — opened from
/// the drawer's avatar. Replaces the legacy /profile route so there's no
/// secondary page to land on: the sheet *is* the settings surface.
class ProfileSheet {
  const ProfileSheet._();

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => const _ProfileSheetBody(),
    );
  }
}

class _ProfileSheetBody extends StatelessWidget {
  const _ProfileSheetBody();

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        final brand = context.brand;
        return Container(
          decoration: BoxDecoration(
            color: brand.bg,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(28),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _SheetHeader(
                onClose: () => Navigator.of(context).maybePop(),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: const [
                    _EmailCard(),
                    SizedBox(height: 18),
                    _ProfileHeaderCard(),
                    SizedBox(height: 18),
                    _SectionLabel('Connections'),
                    SizedBox(height: 8),
                    _IntegrationSection(),
                    SizedBox(height: 18),
                    _SectionLabel('Agent behavior'),
                    SizedBox(height: 8),
                    _GroupedCard(children: [_MorningBriefTile()]),
                    SizedBox(height: 18),
                    _SectionLabel('Appearance'),
                    SizedBox(height: 8),
                    _GroupedCard(children: [_ThemeModeTile()]),
                    SizedBox(height: 18),
                    _SectionLabel('Account'),
                    SizedBox(height: 8),
                    _AccountSection(),
                    if (kDebugMode) ...[
                      SizedBox(height: 18),
                      _SectionLabel('Developer'),
                      SizedBox(height: 8),
                      _DevFlagsSection(),
                    ],
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

// ---------------------------------------------------------------------------
// Sheet chrome
// ---------------------------------------------------------------------------

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          _CircleBtn(
            icon: Icons.close_rounded,
            tooltip: 'Close',
            onTap: onClose,
          ),
          const Spacer(),
          Text(
            AppStrings.profileTitle,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: brand.ink,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          // Symmetry placeholder so the title stays optically centered.
          const SizedBox(width: 42, height: 42),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({
    required this.icon,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final button = Material(
      color: brand.surface,
      shape: CircleBorder(
        side: BorderSide(color: brand.border, width: 0.8),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, size: 18, color: brand.ink),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.4,
          color: brand.textMuted,
        ),
      ),
    );
  }
}

class _EmailCard extends ConsumerWidget {
  const _EmailCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final email = (ref.watch(authProvider).appUser?.email ?? '').trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: brand.border),
      ),
      child: Text(
        email.isEmpty ? 'Signed in' : email,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: brand.ink,
          letterSpacing: -0.2,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared row layout (mirrored from profile_page._PreferenceRow so the sheet
// can stand alone once the legacy /profile page is deleted).
// ---------------------------------------------------------------------------

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final body = Padding(
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
            child: Icon(icon, size: 18, color: iconColor ?? brand.ink),
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
                    color: titleColor ?? brand.ink,
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
          if (trailing != null) ...[
            const SizedBox(width: 12),
            trailing!,
          ],
        ],
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: body),
    );
  }
}

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

class _GroupedCard extends StatelessWidget {
  const _GroupedCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brand.border),
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

// ---------------------------------------------------------------------------
// Profile header — avatar, name, agent-active dot, search criteria
// ---------------------------------------------------------------------------

class _ProfileHeaderCard extends ConsumerWidget {
  const _ProfileHeaderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final user = ref.watch(authProvider).appUser;
    final displayName = user?.displayName ?? 'there';
    final initial = user?.initial ?? 'D';
    final photoUrl = user?.photoUrl;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: brand.border),
      ),
      child: Column(
        children: [
          Row(
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
          const SizedBox(height: 14),
          Divider(height: 1, color: brand.bg),
          const SizedBox(height: 4),
          const _SearchCriteriaRow(label: 'Target roles', value: 'Not set'),
          const _SearchCriteriaRow(label: 'Location', value: 'Not set'),
          const _SearchCriteriaRow(label: 'Comp floor', value: 'Not set'),
          const _SearchCriteriaRow(label: 'Seniority', value: 'Not set'),
        ],
      ),
    );
  }
}

class _SearchCriteriaRow extends StatelessWidget {
  const _SearchCriteriaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return InkWell(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coming soon')),
      ),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: brand.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                color: brand.ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              color: brand.border,
              size: 18,
            ),
          ],
        ),
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

// ---------------------------------------------------------------------------
// Connections
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

// ---------------------------------------------------------------------------
// Agent behavior / Appearance
// ---------------------------------------------------------------------------

class _MorningBriefTile extends ConsumerWidget {
  const _MorningBriefTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final profile = ref.watch(userProfileProvider);
    final enabled = profile?.morningBriefEnabled ?? false;
    final running = ref.watch(
      passiveAgentProvider.select((s) => s.isRunning),
    );
    return _PreferenceRow(
      icon: Icons.wb_sunny_outlined,
      title: "Today's brief",
      subtitle: enabled
          ? (running ? 'Running now…' : 'On — greets you after sign-in')
          : 'Off',
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

// ---------------------------------------------------------------------------
// Account
// ---------------------------------------------------------------------------

class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  Future<void> _confirmAndReset(BuildContext context, WidgetRef ref) async {
    final brand = context.brand;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset account?'),
        content: const Text(
          'This clears every resume, application, pipeline card, saved chat, '
          'and learned fact tied to your account. Your sign-in stays intact. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: brand.warning),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(authProvider.notifier).resetAccountData();
    ref.read(resumeProvider.notifier).clearSelectedResumes();

    if (!context.mounted) return;
    final error = ref.read(authProvider).error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'Account data reset.')),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final loading = ref.watch(authProvider).isLoading;
    return _GroupedCard(
      children: [
        _PreferenceRow(
          icon: Icons.refresh_rounded,
          title: 'Reset account',
          subtitle: 'Clear all data — keep sign-in',
          iconColor: brand.warning,
          titleColor: brand.warning,
          onTap: loading ? null : () => _confirmAndReset(context, ref),
        ),
        const _GroupedDivider(),
        _PreferenceRow(
          icon: Icons.logout_rounded,
          title: loading ? 'Signing out…' : AppStrings.signOut,
          subtitle: 'End your session on this device',
          iconColor: brand.danger,
          titleColor: brand.danger,
          trailing: loading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation(brand.danger),
                  ),
                )
              : null,
          onTap: loading
              ? null
              : () => ref.read(authProvider.notifier).signOut(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Developer (kDebugMode only)
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
          title: 'Show onboarding',
          subtitle: 'Open the onboarding page (auto-clears on submit)',
          trailing: Switch.adaptive(
            value: flags.showOnboarding,
            activeThumbColor: brand.ink,
            onChanged: notifier.setShowOnboarding,
          ),
        ),
        const _GroupedDivider(),
        _PreferenceRow(
          icon: Icons.wb_twilight_outlined,
          title: 'Show morning brief',
          subtitle: 'Open the morning brief (auto-clears on continue)',
          trailing: Switch.adaptive(
            value: flags.showMorningBrief,
            activeThumbColor: brand.ink,
            onChanged: notifier.setShowMorningBrief,
          ),
        ),
        const _GroupedDivider(),
        _PreferenceRow(
          icon: Icons.notifications_active_outlined,
          title: 'Show mock notifications',
          subtitle: 'Seed the inbox with sample agent activity',
          trailing: Switch.adaptive(
            value: flags.showMockNotifications,
            activeThumbColor: brand.ink,
            onChanged: notifier.setShowMockNotifications,
          ),
        ),
      ],
    );
  }
}
