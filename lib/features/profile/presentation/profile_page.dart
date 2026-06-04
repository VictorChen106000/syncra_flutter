import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/dev/dev_flags_notifier.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../core/theme/theme_mode_notifier.dart';
import '../../../data/firestore/firestore_paths.dart';
import '../../../data/firestore/user_repository.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../../shared/widgets/section_title.dart';
import '../../auth/state/auth_notifier.dart';
import '../../auth/state/user_profile_notifier.dart';
import '../../resumes/presentation/widgets/resume_fit_chart.dart';
import '../../resumes/state/resume_notifier.dart';

class _CareerMemoryFact {
  const _CareerMemoryFact({
    required this.id,
    required this.topic,
    required this.detail,
    required this.category,
    required this.observedCount,
  });

  final String id;
  final String topic;
  final String detail;
  final String category;
  final int observedCount;
}

final _careerMemoryProvider =
    StreamProvider.autoDispose<List<_CareerMemoryFact>>((ref) {
      final user = ref.watch(authProvider.select((state) => state.appUser));

      if (user == null || user.isGuest) {
        return Stream.value(const <_CareerMemoryFact>[]);
      }

      final paths = FirestorePaths(FirebaseFirestore.instance);

      return paths
          .learnedFacts(user.uid)
          .orderBy('created_at', descending: true)
          .limit(6)
          .snapshots()
          .map(
            (snapshot) => snapshot.docs
                .map((doc) {
                  final data = doc.data();
                  return _CareerMemoryFact(
                    id: doc.id,
                    topic: (data['topic'] as String?)?.trim() ?? '',
                    detail: (data['detail'] as String?)?.trim() ?? '',
                    category: _normalizeMemoryCategory(
                      data['category']?.toString() ?? '',
                    ),
                    observedCount:
                        (data['observed_count'] as num?)?.toInt() ?? 1,
                  );
                })
                .where(
                  (fact) => fact.topic.isNotEmpty && fact.detail.isNotEmpty,
                )
                .toList(growable: false),
          );
    });

String _formatMemoryTopic(String topic) {
  final words = topic
      .split('_')
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .toList();

  if (words.isEmpty) return 'Career detail';

  return words
      .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
      .join(' ');
}

const _memoryCategories = <String>{
  'skill',
  'experience',
  'preference',
  'constraint',
  'target_role',
  'location',
  'salary',
  'availability',
  'missing_info',
  'other',
};

String _normalizeMemoryCategory(String raw) {
  final normalized = raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');

  if (_memoryCategories.contains(normalized)) return normalized;
  return 'other';
}

String _formatMemoryCategory(String category) {
  return switch (_normalizeMemoryCategory(category)) {
    'skill' => 'Skill',
    'experience' => 'Experience',
    'preference' => 'Preference',
    'constraint' => 'Constraint',
    'target_role' => 'Target role',
    'location' => 'Location',
    'salary' => 'Salary',
    'availability' => 'Availability',
    'missing_info' => 'Missing info',
    _ => 'Other',
  };
}

IconData _memoryCategoryIcon(String category) {
  return switch (_normalizeMemoryCategory(category)) {
    'skill' => Icons.bolt_rounded,
    'experience' => Icons.work_history_rounded,
    'preference' => Icons.tune_rounded,
    'constraint' => Icons.lock_outline_rounded,
    'target_role' => Icons.flag_rounded,
    'location' => Icons.location_on_outlined,
    'salary' => Icons.payments_outlined,
    'availability' => Icons.schedule_rounded,
    'missing_info' => Icons.help_outline_rounded,
    _ => Icons.auto_awesome_rounded,
  };
}

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
                const SectionTitle(title: 'Career Memory'),
                const _CareerMemorySection(),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Resumes'),
                const _ResumesSection(),
                const SizedBox(height: 24),
                const SectionTitle(title: 'Connections'),
                const _IntegrationSection(),
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
// Shared row layout: lime icon chip · title · trailing. Title-only, Gmail-style
// — no subtitle, so the list reads as a calm column of labels.
// Tappable when `onTap` is provided. A destructive row passes `iconColor`,
// which tints both its chip and glyph so meaning never rides on shape alone.
// ---------------------------------------------------------------------------

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
    this.titleColor,
    this.iconColor,
  });

  final IconData icon;
  final String title;
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
          _IconChip(icon: icon, tint: iconColor),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15.5,
                height: 1.2,
                color: titleColor ?? brand.ink,
                letterSpacing: -0.2,
              ),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
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

/// The signature lime chip behind every settings glyph. Default is the full
/// accent with a near-black icon; pass [tint] for a destructive row, which
/// renders a soft tinted box with a full-strength colored icon.
class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, this.tint});

  final IconData icon;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final tinted = tint != null;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: tinted ? tint!.withValues(alpha: 0.14) : brand.accent,
        borderRadius: BorderRadius.circular(11),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 19, color: tinted ? tint! : brand.onAccent),
    );
  }
}

/// Sibling to [_IconChip] for true-colour brand marks: a white chip with a
/// hairline border so a multicolour logo (Gmail) reads cleanly in either theme.
class _BrandLogoChip extends StatelessWidget {
  const _BrandLogoChip({required this.asset, required this.semanticsLabel});

  final String asset;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: brand.ink.withValues(alpha: 0.08)),
      ),
      alignment: Alignment.center,
      child: SvgPicture.asset(
        asset,
        width: 22,
        height: 22,
        semanticsLabel: semanticsLabel,
      ),
    );
  }
}

/// Tiny icon-only segmented selector — three choices in a single pill.
/// Active option flips to a lime background with a near-black icon.
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
                  color: value == selected ? brand.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 14,
                  color: value == selected ? brand.onAccent : brand.textMuted,
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
    final role = (profile?.role ?? '').trim();
    final resumeFit = profile?.resumeFit;
    final hasFit = resumeFit != null && resumeFit.segments.isNotEmpty;

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
                      const SizedBox(height: 3),
                      Text(
                        email,
                        style: TextStyle(
                          color: brand.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
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
          // The agent's resume-fit read, rendered as the same interactive donut
          // used in chat and the dashboard — the dominant strength is
          // pre-focused, so the headline number reads at a glance.
          if (hasFit) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Strengths',
                style: TextStyle(
                  color: brand.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.1,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ResumeFitChart(fit: resumeFit),
          ],
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
      decoration: BoxDecoration(color: brand.accent, shape: BoxShape.circle),
      child: ClipOval(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: Text(
                initial,
                style: TextStyle(
                  color: brand.onAccent,
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

// ---------------------------------------------------------------------------
// Career Memory — reusable facts the agent learned from user answers.
// The agent writes facts through `remember_fact`; the user can delete one
// memory, clear all Career Memory, or reset the account.
// ---------------------------------------------------------------------------

class _CareerMemorySection extends ConsumerWidget {
  const _CareerMemorySection();

  Future<void> _confirmAndClearMemory(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final brand = dialogContext.brand;

        return AlertDialog(
          backgroundColor: brand.surface,
          title: Text(
            'Clear Career Memory?',
            style: TextStyle(color: brand.ink, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'This removes the facts Syncra learned from your answers. '
            'Your resumes, jobs, and applications will stay.',
            style: TextStyle(color: brand.textMuted, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Clear memory'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final user = ref.read(authProvider).appUser;
    if (user == null || user.isGuest) return;

    try {
      await UserRepository().clearLearnedFacts(user.uid);
      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Career Memory cleared.')));
    } catch (_) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not clear Career Memory. Try again.'),
        ),
      );
    }
  }

  Future<void> _confirmAndDeleteFact(
    BuildContext context,
    WidgetRef ref,
    _CareerMemoryFact fact,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final brand = dialogContext.brand;
        final topic = _formatMemoryTopic(fact.topic);

        return AlertDialog(
          backgroundColor: brand.surface,
          title: Text(
            'Delete this memory?',
            style: TextStyle(color: brand.ink, fontWeight: FontWeight.w800),
          ),
          content: Text(
            '"$topic" will be removed from Syncra Career Memory. '
            'Your resumes, jobs, and applications will stay.',
            style: TextStyle(color: brand.textMuted, height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Delete memory'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final user = ref.read(authProvider).appUser;
    if (user == null || user.isGuest) return;

    try {
      await UserRepository().deleteLearnedFact(user.uid, fact.id);
      if (!context.mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Career Memory removed.')));
    } catch (_) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not remove this memory. Try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final factsAsync = ref.watch(_careerMemoryProvider);

    return factsAsync.when(
      data: (facts) {
        if (facts.isEmpty) {
          return const _GroupedCard(children: [_CareerMemoryEmptyRow()]);
        }

        final visibleFacts = facts.take(3).toList(growable: false);

        return _GroupedCard(
          children: [
            _CareerMemorySummaryRow(
              count: facts.length,
              onClear: () => _confirmAndClearMemory(context, ref),
            ),
            for (var i = 0; i < visibleFacts.length; i++) ...[
              const _GroupedDivider(),
              _CareerMemoryFactRow(
                fact: visibleFacts[i],
                onDelete: () =>
                    _confirmAndDeleteFact(context, ref, visibleFacts[i]),
              ),
            ],
          ],
        );
      },
      loading: () => const _GroupedCard(children: [_CareerMemoryLoadingRow()]),
      error: (_, _) => const _GroupedCard(children: [_CareerMemoryErrorRow()]),
    );
  }
}

class _CareerMemorySummaryRow extends StatelessWidget {
  const _CareerMemorySummaryRow({required this.count, required this.onClear});

  final int count;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final label = count == 1 ? '1 learned fact' : '$count learned facts';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const _IconChip(icon: Icons.psychology_alt_rounded),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Syncra memory',
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Used to improve matching, tailoring, and outreach.',
                  style: TextStyle(
                    color: brand.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: brand.surfaceMuted,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(
                  foregroundColor: brand.danger,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CareerMemoryFactRow extends StatelessWidget {
  const _CareerMemoryFactRow({required this.fact, required this.onDelete});

  final _CareerMemoryFact fact;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconChip(
            icon: _memoryCategoryIcon(fact.category),
            tint: brand.textSoft,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _CareerMemoryMetaChip(
                      label: _formatMemoryCategory(fact.category),
                    ),
                    if (fact.observedCount > 1)
                      _CareerMemoryMetaChip(
                        label: 'Seen ${fact.observedCount}x',
                        muted: true,
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  _formatMemoryTopic(fact.topic),
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  fact.detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: brand.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Delete memory',
            onPressed: onDelete,
            visualDensity: VisualDensity.compact,
            style: IconButton.styleFrom(
              foregroundColor: brand.textMuted,
              minimumSize: const Size(36, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

class _CareerMemoryMetaChip extends StatelessWidget {
  const _CareerMemoryMetaChip({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: muted ? brand.surfaceMuted : brand.accentMuted,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
          color: muted ? brand.border : brand.accent.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: muted ? brand.textMuted : brand.ink,
          fontSize: 10.8,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.05,
        ),
      ),
    );
  }
}

class _CareerMemoryEmptyRow extends StatelessWidget {
  const _CareerMemoryEmptyRow();

  @override
  Widget build(BuildContext context) {
    return const _CareerMemoryStatusRow(
      icon: Icons.psychology_alt_rounded,
      title: 'No career memory yet',
      body:
          'When you answer follow-up questions, reusable skills and preferences will appear here.',
    );
  }
}

class _CareerMemoryLoadingRow extends StatelessWidget {
  const _CareerMemoryLoadingRow();

  @override
  Widget build(BuildContext context) {
    return const _CareerMemoryStatusRow(
      icon: Icons.hourglass_empty_rounded,
      title: 'Loading career memory…',
      body: 'Checking what Syncra has learned from your previous answers.',
    );
  }
}

class _CareerMemoryErrorRow extends StatelessWidget {
  const _CareerMemoryErrorRow();

  @override
  Widget build(BuildContext context) {
    return const _CareerMemoryStatusRow(
      icon: Icons.error_outline_rounded,
      title: 'Could not load career memory',
      body: 'Your saved facts are still protected. Try again later.',
    );
  }
}

class _CareerMemoryStatusRow extends StatelessWidget {
  const _CareerMemoryStatusRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _IconChip(icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: TextStyle(
                    color: brand.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
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
        Icon(Icons.chevron_right_rounded, color: brand.border, size: 18),
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
          svgAsset: AppAssets.gmailSvg,
          title: 'Gmail',
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
    required this.active,
    required this.onToggle,
    this.svgAsset,
  });

  final IconData icon;
  final String title;
  final bool active;
  final VoidCallback? onToggle;

  /// Optional brand logo (e.g. the multicolour Gmail mark) rendered on a white
  /// chip in place of the lime accent icon, so the logo stays true to colour.
  final String? svgAsset;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          if (svgAsset != null)
            _BrandLogoChip(asset: svgAsset!, semanticsLabel: title)
          else
            _IconChip(icon: icon),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15.5,
                height: 1.2,
                color: brand.ink,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(width: 12),
          _LimeToggle(active: active, onToggle: onToggle),
        ],
      ),
    );
  }
}

/// Pill switch that fills lime when on and stays a neutral track when off —
/// the thumb position carries the state too, so it never reads on colour alone.
class _LimeToggle extends StatelessWidget {
  const _LimeToggle({required this.active, required this.onToggle});

  final bool active;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: 46,
        height: 28,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(99),
          color: active ? brand.accent : brand.surfaceMuted,
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: active ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? brand.onAccent : brand.textSoft,
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
    return const _GroupedCard(children: [_ThemeModeTile()]);
  }
}

class _ThemeModeTile extends ConsumerWidget {
  const _ThemeModeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(themeModeProvider);
    return _PreferenceRow(
      icon: Icons.contrast_rounded,
      title: 'Theme',
      trailing: _MiniSegmented<ThemeMode>(
        selected: selected,
        onChanged: (m) => ref.read(themeModeProvider.notifier).setMode(m),
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
          'and learned fact tied to your account, then starts you over from '
          'onboarding. Your sign-in stays intact. This cannot be undone.',
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
    final error = ref.read(authProvider).error;

    if (error != null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }

    // Reset succeeded. Drop in-memory state that mirrors the now-empty
    // Firestore data, then snap the profile back to first-run — the router
    // redirect keys off `hasCompletedOnboarding` and routes us to onboarding,
    // so no manual navigation (or success snackbar) is needed here.
    ref.read(resumeProvider.notifier).clearSelectedResumes();
    ref.read(userProfileProvider.notifier).resetToFirstRun();
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
          iconColor: brand.warning,
          titleColor: brand.warning,
          onTap: loading ? null : () => _confirmAndReset(context, ref),
        ),
        const _GroupedDivider(),
        _PreferenceRow(
          icon: Icons.logout_rounded,
          title: loading ? 'Signing out…' : AppStrings.signOut,
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
          trailing: Switch.adaptive(
            value: flags.showOnboarding,
            activeThumbColor: brand.onAccent,
            activeTrackColor: brand.accent,
            onChanged: notifier.setShowOnboarding,
          ),
        ),
        const _GroupedDivider(),
        _PreferenceRow(
          icon: Icons.wb_twilight_outlined,
          title: 'Show morning brief',
          trailing: Switch.adaptive(
            value: flags.showMorningBrief,
            activeThumbColor: brand.onAccent,
            activeTrackColor: brand.accent,
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
      padding: const EdgeInsets.only(left: 68),
      child: Divider(height: 1, color: brand.bg),
    );
  }
}
