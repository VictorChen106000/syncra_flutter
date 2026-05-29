import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../agent/state/passive_agent_notifier.dart';
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
                const SectionTitle(title: 'Resumes'),
                const _ResumesSection(),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Connections'),
                const _IntegrationSection(),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Agent behavior'),
                const _AgentBehaviorSection(),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Appearance'),
                const _AppearanceSection(),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Account'),
                const _AccountSection(),
                if (kDebugMode) ...const [
                  SizedBox(height: 24),
                  SectionTitle(title: 'Developer'),
                  _DevFlagsSection(),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared row layout: icon · title (+ subtitle) · trailing.
// Tappable when `onTap` is provided; title / icon color overridable so the
// Account section can tint destructive rows without a separate widget.
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
    final profile = ref.watch(userProfileProvider);
    final displayName = user?.displayName ?? 'there';
    final initial = user?.initial ?? 'D';
    final email = user?.email ?? '';
    final photoUrl = user?.photoUrl;
    final agentActive = profile?.isAgentActive ?? true;
    final role = (profile?.role ?? '').trim();
    final fitSegments = profile?.resumeFit?.segments ?? const [];
    final topStrength = fitSegments.isNotEmpty ? fitSegments.first : null;

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
                        _PulsingActiveDot(active: agentActive),
                        const SizedBox(width: 8),
                        Text(
                          agentActive ? 'Agent active' : 'Agent paused',
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
          const SizedBox(height: 16),
          Divider(height: 1, color: brand.bg),
          const SizedBox(height: 4),
          // Real, agent-captured search context — the role onboarding set and
          // the dominant strength the resume analysis read. No placeholders:
          // rows only appear once there's actual data behind them.
          _SearchCriteriaRow(
            label: 'Target role',
            value: role.isEmpty ? 'Not set yet' : role,
          ),
          if (topStrength != null)
            _SearchCriteriaRow(
              label: 'Top strength',
              value: '${topStrength.label} · ${topStrength.percent.round()}%',
            ),
        ],
      ),
    );
  }
}

/// Plain text row for the agent's search criteria, embedded inside the
/// profile header card. No leading icon — the section frames itself.
class _SearchCriteriaRow extends StatelessWidget {
  const _SearchCriteriaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // Read-only summary of what the agent infers about the user's search.
    // Editing happens via the agent thread, so these rows aren't tappable.
    return Padding(
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
  const _PulsingActiveDot({this.active = true});

  /// When false the dot stops pulsing and renders a muted, static state —
  /// reflecting `UserProfile.isAgentActive` instead of always reading "live".
  final bool active;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (!active) {
      return Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: brand.textSoft,
          shape: BoxShape.circle,
        ),
      );
    }
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
// Resumes — entry point into the resume library (base uploads + tailored
// variants). Trailing chip shows the combined count.
// ---------------------------------------------------------------------------

class _ResumesSection extends ConsumerWidget {
  const _ResumesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(resumeProvider);
    final count = state.resumes.length + state.tailoredResumes.length;
    return _GroupedCard(
      children: [
        _PreferenceRow(
          icon: Icons.description_outlined,
          title: 'Resume library',
          subtitle: count == 0
              ? 'Upload a resume to get started'
              : '$count saved — base and tailored',
          trailing: _CountChip(count: count),
          onTap: () => context.go(RouteNames.resumes),
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: brand.surfaceMuted,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              color: brand.ink,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Icon(
          Icons.chevron_right_rounded,
          color: brand.border,
          size: 18,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Connections — third-party integrations. Gmail send/draft authorizes
// on-demand at send time (GmailService), so this toggle records the user's
// intent in their profile (`gmail_connected`) rather than keeping throwaway
// local state that resets on every visit.
// ---------------------------------------------------------------------------

class _IntegrationSection extends ConsumerWidget {
  const _IntegrationSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final connected = profile?.gmailConnected ?? false;
    return _GroupedCard(
      children: [
        _IntegrationTile(
          icon: Icons.mail_outline_rounded,
          title: 'Gmail Workspace',
          subtitle: 'Allow Agent to draft outreach and parse rejections',
          active: connected,
          onToggle: profile == null
              ? null
              : () => ref
                  .read(userProfileProvider.notifier)
                  .setGmailConnected(!connected),
        ),
      ],
    );
  }
}

class _IntegrationTile extends StatelessWidget {
  const _IntegrationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.onToggle,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool active;
  final VoidCallback? onToggle;

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
              color: active ? brand.accent : brand.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: active ? brand.onAccent : brand.textSoft,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: brand.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
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
                color: active ? brand.ink : brand.border,
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                alignment:
                    active ? Alignment.centerRight : Alignment.centerLeft,
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

// ---------------------------------------------------------------------------
// Agent behavior — how the agent acts on your behalf.
// ---------------------------------------------------------------------------

class _AgentBehaviorSection extends StatelessWidget {
  const _AgentBehaviorSection();

  @override
  Widget build(BuildContext context) {
    return const _GroupedCard(
      children: [
        _AgentActiveTile(),
        _GroupedDivider(),
        _MorningBriefTile(),
        _GroupedDivider(),
        _RunBriefTile(),
      ],
    );
  }
}

/// Master switch for whether the agent acts on the user's behalf. Wires the
/// previously-orphaned `UserProfileNotifier.setAgentActive` to a real control,
/// and the profile header's status dot reflects it.
class _AgentActiveTile extends ConsumerWidget {
  const _AgentActiveTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final profile = ref.watch(userProfileProvider);
    final active = profile?.isAgentActive ?? true;
    return _PreferenceRow(
      icon: Icons.bolt_rounded,
      title: 'Agent active',
      subtitle: active
          ? 'Syncra works on your behalf'
          : 'Paused — Syncra waits for you',
      trailing: Switch.adaptive(
        value: active,
        activeThumbColor: brand.ink,
        onChanged: profile == null
            ? null
            : (v) =>
                ref.read(userProfileProvider.notifier).setAgentActive(v),
      ),
    );
  }
}

/// Triggers the passive agent's job brief on demand and opens the morning
/// brief surface so the run is visible. Lets anyone (developer or user) watch
/// the brief end-to-end without waiting for a sign-in cycle.
class _RunBriefTile extends ConsumerWidget {
  const _RunBriefTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final running = ref.watch(
      passiveAgentProvider.select((s) => s.isRunning),
    );
    return _PreferenceRow(
      icon: Icons.play_circle_outline_rounded,
      title: running ? 'Brief running…' : "Run today's brief",
      subtitle: 'Scan fresh roles and open the brief',
      trailing: running
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(brand.ink),
              ),
            )
          : Icon(Icons.chevron_right_rounded, color: brand.border, size: 20),
      onTap: running
          ? null
          : () {
              // Kick the brief off, then open the morning-brief surface so the
              // run is visible. The page no-ops the launch if one is already
              // in flight, so this stays safe to tap repeatedly.
              ref.read(passiveAgentProvider.notifier).runBrief();
              context.go(RouteNames.morningBrief);
            },
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
        // Flipping the toggle only stores the preference — it never fires the
        // brief itself (no surprise token spend). The brief runs when the
        // user taps "Run today's brief" or sees it after sign-in.
        onChanged: profile == null
            ? null
            : (v) => ref
                .read(userProfileProvider.notifier)
                .setMorningBriefEnabled(v),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Appearance — visual prefs only.
// ---------------------------------------------------------------------------

class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context) {
    return const _GroupedCard(
      children: [
        _ThemeModeTile(),
      ],
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
// Account — reset (warning) and sign out (danger) grouped in one card so the
// destructive actions live together instead of stacked full-width buttons.
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

    // Drop in-memory state that mirrors the now-empty Firestore data so the
    // UI snaps to a clean slate without waiting for streams to settle.
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
      ],
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
