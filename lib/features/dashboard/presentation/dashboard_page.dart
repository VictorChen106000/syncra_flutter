import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../core/utils/motion.dart';
import '../../../data/models/tracked_application.dart';
import '../../agent_chat/agent_prompt_suggestions.dart';
import '../../agent_chat/models/agent_block.dart';
import '../../agent_chat/models/chat_message.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../../shared/widgets/gooey_orb.dart';
import '../../agent/state/passive_agent_notifier.dart';
import '../../agent_chat/state/agent_chat_notifier.dart';
import '../../applications/state/applications_notifier.dart';
import '../../jobs/state/jobs_notifier.dart';
import '../../auth/state/auth_notifier.dart';
import '../../auth/state/user_profile_notifier.dart';
import '../../notifications/presentation/notifications_drawer.dart';
import '../../notifications/state/notifications_notifier.dart';
import '../../resumes/presentation/widgets/resume_fit_chart.dart';
import '../../resumes/state/resume_notifier.dart';

/// Approximate vertical footprint of the bottom-anchored agent area
/// (prompt suggestions + input bar + bottom inset). Used as scroll-view
/// bottom padding so content never disappears behind the floating block
/// on short screens.
const double _kFloatingAreaReservedHeight =
    AppConstants.floatingInputBottom + 140 + AppConstants.smallGap + 72;

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScreen(
      showBottomNav: false,
      activeTab: BottomNavTab.home,
      extendBehindBottomNav: true,
      drawer: const NotificationsDrawer(),
      drawerEdgeDragWidth: 48,
      onDrawerChanged: (open) =>
          ref.read(notificationsDrawerOpenProvider.notifier).state = open,
      child: Stack(
        children: [
          Column(
            children: [
              _DashboardHeader(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // ConstrainedBox lets the scroll child stretch to the
                    // visible viewport — without it, a Center inside the
                    // _AgentSection would collapse to the chart's intrinsic
                    // height and hug the profile header instead of sitting
                    // optically between header and floating input area.
                    final minBodyHeight =
                        (constraints.maxHeight -
                                12 -
                                _kFloatingAreaReservedHeight)
                            .clamp(0.0, double.infinity);
                    return SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.screenHorizontalPadding,
                        12,
                        AppConstants.screenHorizontalPadding,
                        _kFloatingAreaReservedHeight,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: minBodyHeight),
                        child: const _AgentSection(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const _FloatingAgentArea(),
        ],
      ),
    );
  }
}

class _DashboardHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final hasUnread = ref.watch(
      notificationsProvider.select((s) => s.unreadCount > 0),
    );
    final user = auth.appUser;
    return AppHeader.home(
      avatar: _Avatar(
        photoUrl: user?.photoUrl,
        showBadge: hasUnread,
        onTap: () => Scaffold.of(context).openDrawer(),
      ),
      name: user?.displayName ?? 'there',
      role: AppStrings.dashboardGreetingRole,
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.photoUrl,
    required this.showBadge,
    required this.onTap,
  });

  final String? photoUrl;
  final bool showBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hasNetworkPhoto = photoUrl != null && photoUrl!.isNotEmpty;
    final ImageProvider image = hasNetworkPhoto
        ? NetworkImage(photoUrl!)
        : const AssetImage(AppAssets.profileImage);

    return Semantics(
      label: showBadge ? 'Notifications, unread' : 'Notifications',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: brand.ink,
                  border: Border.all(color: brand.surface, width: 2),
                  image: DecorationImage(
                    image: image,
                    fit: BoxFit.cover,
                    onError: (_, _) {},
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: brand.shadow,
                      blurRadius: 12,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
              if (showBadge)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: brand.danger,
                      shape: BoxShape.circle,
                      border: Border.all(color: brand.bg, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Agent hero area — card fan once a pipeline exists, gooey-orb empty state
// before the agent has surfaced anything.
// ---------------------------------------------------------------------------

/// Switches the dashboard's hero area between the agent card fan (once the
/// agent has built a pipeline) and the resume-fit donut chart.
enum _AgentView { cards, chart }

class _AgentSection extends ConsumerStatefulWidget {
  const _AgentSection();

  @override
  ConsumerState<_AgentSection> createState() => _AgentSectionState();
}

class _AgentSectionState extends ConsumerState<_AgentSection> {
  /// User's manual choice, or null while the section is still auto-picking
  /// a view. We auto-pick so the post-onboarding flow lands on the chart
  /// (calm, informative) and then promotes itself to the card stack the
  /// moment the brief produces a pipeline — without overriding a user who
  /// has explicitly tapped the swap icon.
  _AgentView? _override;

  void _setView(_AgentView v) => setState(() => _override = v);

  _AgentView _resolveView({required bool hasPipeline, required bool hasFit}) {
    if (_override != null) return _override!;
    // Pipeline takes precedence — that's the "work to do". Otherwise show
    // the fit chart while the brief is still warming up so the user has
    // something to read instead of an empty stage.
    if (hasPipeline) return _AgentView.cards;
    if (hasFit) return _AgentView.chart;
    return _AgentView.cards;
  }

  @override
  Widget build(BuildContext context) {
    final pipelineCards = ref.watch(jobsProvider.select((s) => s.cards));
    final hasPipeline = pipelineCards.isNotEmpty;
    final resumeFit = ref.watch(
      userProfileProvider.select((p) => p?.resumeFit),
    );

    final view = _resolveView(
      hasPipeline: hasPipeline,
      hasFit: resumeFit != null,
    );

    // The swap icon is only meaningful when BOTH sides have something to show.
    // Otherwise the dashboard collapses to whichever side has data, with no
    // toggle (no need to offer a swap that lands on an empty state).
    final canShowToggle = hasPipeline && resumeFit != null;

    final Widget body;
    if (view == _AgentView.chart && resumeFit != null) {
      // Center vertically in the scroll viewport (the parent ConstrainedBox
      // gives us the full height to work with) so the donut sits optically
      // between the profile header and the floating input area.
      body = Center(child: ResumeFitChart(fit: resumeFit));
    } else if (hasPipeline) {
      body = const _AgentCardStack();
    } else {
      body = const _DashboardAgentEmptyState();
    }

    if (!canShowToggle) return body;

    // Toggle sits in a tight top-right slot so it reads as a control on the
    // section, not its own surface. AnimatedSwitcher cross-fades the body so
    // the swap doesn't snap.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: _AgentViewSwap(
            view: view,
            onTap: () => _setView(
              view == _AgentView.cards ? _AgentView.chart : _AgentView.cards,
            ),
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, anim) =>
                FadeTransition(opacity: anim, child: child),
            child: KeyedSubtree(key: ValueKey(view), child: body),
          ),
        ),
      ],
    );
  }
}

/// Single-icon swap control anchored to the top-right of the agent section.
/// Tapping flips the view; the icon morphs (cards ↔ donut) to telegraph what
/// the *next* tap will reveal — i.e. it shows the OTHER view's icon, not the
/// current one. Matches how iOS Photos / Apple Music phrase their view
/// toggles.
class _AgentViewSwap extends StatelessWidget {
  const _AgentViewSwap({required this.view, required this.onTap});

  final _AgentView view;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final showingCards = view == _AgentView.cards;
    final nextIcon = showingCards
        ? Icons.donut_small_rounded
        : Icons.style_rounded;
    final nextLabel = showingCards ? 'Show chart' : 'Show cards';
    return Tooltip(
      message: nextLabel,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: brand.surfaceMuted,
            ),
            alignment: Alignment.center,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              transitionBuilder: (child, anim) => RotationTransition(
                turns: Tween<double>(begin: 0.85, end: 1).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Icon(
                nextIcon,
                key: ValueKey(nextIcon),
                size: 18,
                color: brand.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown before the agent has tailored anything into a pipeline — a glassy
/// orb and a warm greeting, mirroring the chat page's empty state.
class _DashboardAgentEmptyState extends ConsumerWidget {
  const _DashboardAgentEmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final fullName = (ref.watch(authProvider).appUser?.displayName ?? '')
        .trim();
    final firstName = fullName.isEmpty
        ? ''
        : fullName.split(RegExp(r'\s+')).first;
    // When the passive agent is mid-brief (most likely the first one auto-
    // fired by onboarding), swap the generic greeting for a live status that
    // names the target role. This is the UX bridge between onboarding's
    // "I'll find roles for you" promise and the dashboard's empty state —
    // the user lands on visible activity, not stillness.
    final isRunning = ref.watch(
      passiveAgentProvider.select((s) => s.isRunning),
    );
    final role = (ref.watch(userProfileProvider)?.role ?? '').trim();

    final String headline;
    final String? subline;
    if (isRunning && role.isNotEmpty) {
      headline = 'Looking for $role roles…';
      subline = "I'll drop matches here as I find them.";
    } else if (isRunning) {
      headline = 'Scanning roles…';
      subline = "I'll drop matches here as I find them.";
    } else if (firstName.isEmpty) {
      headline = 'How can I help you?';
      subline = null;
    } else {
      headline = 'How can I help you, $firstName?';
      subline = null;
    }

    return Padding(
      padding: const EdgeInsets.only(top: 44, bottom: 8),
      child: Column(
        children: [
          GooeyOrb(size: 150)
              .animate()
              .fadeIn(duration: 500.ms)
              .scale(
                begin: const Offset(0.8, 0.8),
                end: const Offset(1, 1),
                curve: Curves.easeOutCubic,
              ),
          const SizedBox(height: 26),
          Text(
                headline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: brand.ink,
                  letterSpacing: -0.5,
                  height: 1.2,
                ),
              )
              .animate(delay: 120.ms)
              .fadeIn(duration: 420.ms)
              .moveY(begin: 8, end: 0, curve: Curves.easeOutCubic),
          if (subline != null) ...[
            const SizedBox(height: 10),
            Text(
              subline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: brand.textMuted,
                height: 1.4,
                letterSpacing: -0.1,
              ),
            ).animate(delay: 220.ms).fadeIn(duration: 420.ms),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Agent fan-stack
// ---------------------------------------------------------------------------

class _AgentCardStack extends ConsumerStatefulWidget {
  const _AgentCardStack();

  @override
  ConsumerState<_AgentCardStack> createState() => _AgentCardStackState();
}

class _AgentCardStackState extends ConsumerState<_AgentCardStack> {
  static const double _maxCardWidth = 320;
  static const double _cardHeight = 180;
  static const double _stackHeight = 290;
  static const double _cardLeftInset = 6;
  static const double _fanRightMargin = 48;
  static const Duration _animDuration = Duration(milliseconds: 550);

  // Slot-based palette: front slot is full brand lime, deeper slots step
  // toward a saturated forest tone. Bound to the slot position, not the
  // dataset, so reordering preserves the lime→deep gradient.
  static const Color _deepGreen = Color(0xFF1E4D14);
  static final List<Color> _slotBackgrounds = [
    AppColors.accent,
    Color.lerp(AppColors.accent, _deepGreen, 0.30)!,
    Color.lerp(AppColors.accent, _deepGreen, 0.52)!,
  ];
  static const List<double> _slotMutedAlpha = [0.62, 0.70, 0.80];

  bool _expanded = false;
  bool _prevExpanded = false;
  bool _everInteracted = false;
  final List<int> _order = [0, 1, 2];
  List<int> _prevOrder = [0, 1, 2];
  int _version = 0;

  void _animate(VoidCallback mutate) {
    setState(() {
      _prevExpanded = _expanded;
      _prevOrder = List<int>.from(_order);
      mutate();
      _version++;
      _everInteracted = true;
    });
  }

  void _onCardTap(int cardIdx) {
    HapticFeedback.selectionClick();
    if (!_expanded) {
      _animate(() => _expanded = true);
      return;
    }
    final slot = _order.indexOf(cardIdx);
    if (slot == 0) {
      _animate(() => _expanded = false);
    } else {
      _animate(() {
        _order.remove(cardIdx);
        _order.insert(0, cardIdx);
      });
    }
  }

  void _onOutsideTap() {
    if (!_expanded) return;
    HapticFeedback.selectionClick();
    _animate(() => _expanded = false);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final missionCards = ref.watch(jobsProvider.select((s) => s.cards));
    final resumeState = ref.watch(resumeProvider);
    final appState = ref.watch(applicationsProvider);

    final activeMissionCount = missionCards
        .where((card) => !card.isSent)
        .length;
    final approvalMissionCount = missionCards
        .where((card) => card.needsYou)
        .length;

    final missionSubtitle = approvalMissionCount > 0
        ? '$activeMissionCount active · '
              '${approvalMissionCount == 1 ? '1 needs approval' : '$approvalMissionCount need approval'}'
        : activeMissionCount == 1
        ? '1 active mission'
        : '$activeMissionCount active missions';
    final draftCount = appState.countOf(ApplicationPhase.draft);
    final sentCount = appState.countOf(ApplicationPhase.sent);

    // Green-gradient fan: the front SLOT is always the full brand lime; each
    // slot behind it steps DOWN into deeper, still-saturated green (lerping
    // toward a deep forest tone) rather than washing toward white — a white
    // wash desaturates the neon lime into a sickly pastel. Colors are bound
    // to the slot, not the dataset, so the stack keeps its lime→deep gradient
    // even when the user reorders cards. onAccent (near-black) stays readable
    // on every step, with muted text darkened on the deeper slots so the
    // small kicker label keeps a 4.5:1 contrast ratio.
    final cardFg = brand.onAccent;

    final cards = <_StackCardData>[
      // 1 — jobs the agent surfaced, awaiting the user's review.
      _StackCardData(
        title: 'Mission Control',
        kicker: approvalMissionCount > 0 ? 'Needs Approval' : 'Active Missions',
        subtitle: missionSubtitle,
        count: activeMissionCount,
        foreground: cardFg,
        icon: Icons.work_outline_rounded,
        route: RouteNames.jobs,
      ),
      // 2 — resumes the agent has already tailored, ready to attach.
      _StackCardData(
        title: 'Tailored Resumes',
        kicker: 'Ready to Send',
        subtitle: '${resumeState.resumes.length} uploaded',
        count: resumeState.tailoredResumes.length,
        foreground: cardFg,
        icon: Icons.auto_awesome_rounded,
        route: RouteNames.resumes,
      ),
      // 3 — applications in flight (drafted / sent).
      _StackCardData(
        title: 'Applications',
        kicker: 'In Progress',
        subtitle: '$draftCount drafts · $sentCount sent',
        count: appState.items.length,
        foreground: cardFg,
        icon: Icons.send_rounded,
        route: RouteNames.applications,
      ),
    ];

    // Audit item #9: fade the instruction hint after first interaction.
    final hint = _everInteracted ? '' : 'TAP THE STACK TO POP OUT';
    final showHint = hint.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: showHint
                ? Padding(
                    key: const ValueKey('hint'),
                    padding: const EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      hint,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                        color: brand.textMuted,
                      ),
                    ),
                  )
                : const SizedBox(key: ValueKey('empty'), height: 0),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _expanded ? _onOutsideTap : null,
          child:
              SizedBox(
                height: _stackHeight,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = math.min(
                      _maxCardWidth,
                      constraints.maxWidth - _cardLeftInset - _fanRightMargin,
                    );
                    return TweenAnimationBuilder<double>(
                      key: ValueKey(_version),
                      tween: Tween(begin: 0, end: 1),
                      duration: _animDuration,
                      curve: Curves.easeOutCubic,
                      builder: (context, t, _) {
                        final paintOrder = _order.reversed.toList();
                        return Stack(
                          clipBehavior: Clip.none,
                          children: [
                            for (final cardIdx in paintOrder)
                              _buildCard(cards[cardIdx], cardIdx, t, cardWidth),
                          ],
                        );
                      },
                    );
                  },
                ),
              ).animate().shake(
                delay: 900.ms,
                duration: 650.ms,
                hz: 3,
                rotation: 0.018,
              ),
        ),
      ],
    );
  }

  double _lerp(double a, double b, double t) => a + (b - a) * t;

  Widget _buildCard(
    _StackCardData data,
    int cardIdx,
    double t,
    double cardWidth,
  ) {
    final prevSlotI = _prevOrder.indexOf(cardIdx);
    final newSlotI = _order.indexOf(cardIdx);
    final prevSlot = prevSlotI.toDouble();
    final newSlot = newSlotI.toDouble();
    final slot = _lerp(prevSlot, newSlot, t);

    final prevExpand = _prevExpanded ? 1.0 : 0.0;
    final newExpand = _expanded ? 1.0 : 0.0;
    final expand = _lerp(prevExpand, newExpand, t);

    final collapsedRot = slot * 6.0;
    final collapsedX = slot * 16.0;
    final collapsedY = slot * 14.0;

    final expandedRot = -4.0 + slot * 8.0;
    final expandedX = slot * 22.0;
    final expandedY = slot * 22.0;

    final rotDeg = _lerp(collapsedRot, expandedRot, expand);
    final tx = _lerp(collapsedX, expandedX, expand);
    final ty = _lerp(collapsedY, expandedY, expand);

    // Slot-derived colors, tweened alongside position so the front slot is
    // always lime, the back slot always deep, even mid-reorder.
    final background = Color.lerp(
      _slotBackgrounds[prevSlotI],
      _slotBackgrounds[newSlotI],
      t,
    )!;
    final mutedAlpha = _lerp(
      _slotMutedAlpha[prevSlotI],
      _slotMutedAlpha[newSlotI],
      t,
    );
    final foregroundMuted = data.foreground.withValues(alpha: mutedAlpha);

    return Positioned(
      left: _cardLeftInset,
      top: 40,
      child: Transform.translate(
        offset: Offset(tx, ty),
        child: Transform.rotate(
          angle: rotDeg * math.pi / 180,
          alignment: Alignment.bottomLeft,
          origin: const Offset(28, -24),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onCardTap(cardIdx),
            child: _StackCard(
              data: data,
              background: background,
              foregroundMuted: foregroundMuted,
              width: cardWidth,
              height: _cardHeight,
              showAction: _expanded,
            ),
          ),
        ),
      ),
    );
  }
}

class _StackCardData {
  const _StackCardData({
    required this.title,
    required this.kicker,
    required this.subtitle,
    required this.count,
    required this.foreground,
    required this.icon,
    required this.route,
  });

  final String title;
  final String kicker;
  final String subtitle;
  final int count;
  final Color foreground;
  final IconData icon;
  final String route;
}

class _StackCard extends StatelessWidget {
  const _StackCard({
    required this.data,
    required this.background,
    required this.foregroundMuted,
    required this.width,
    required this.height,
    required this.showAction,
  });

  final _StackCardData data;
  final Color background;
  final Color foregroundMuted;
  final double width;
  final double height;
  final bool showAction;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final fg = data.foreground;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppConstants.largeCardRadius),
        border: Border.all(color: brand.shadow.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: brand.shadow,
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(data.icon, color: fg, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      data.kicker.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.6,
                        color: foregroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${data.count}',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1,
                  letterSpacing: -1.2,
                  color: fg,
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      data.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.4,
                        height: 1.05,
                        color: fg,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      data.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.1,
                        color: foregroundMuted,
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedSlide(
                offset: showAction ? Offset.zero : const Offset(0.3, 0),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: showAction ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: Material(
                    color: fg.withValues(alpha: 0.10),
                    shape: const StadiumBorder(),
                    child: InkWell(
                      customBorder: const StadiumBorder(),
                      onTap: showAction ? () => context.go(data.route) : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Open',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                color: fg,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              size: 14,
                              color: fg,
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _FloatingAgentArea extends StatelessWidget {
  const _FloatingAgentArea();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: AppConstants.floatingInputBottom,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          _PromptSuggestions(),
          SizedBox(height: AppConstants.smallGap),
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppConstants.screenHorizontalPadding,
            ),
            child: _AgentInputBar(),
          ),
        ],
      ),
    );
  }
}

class _PromptSuggestions extends StatelessWidget {
  const _PromptSuggestions();

  static const _items = <_PromptSuggestionData>[
    _PromptSuggestionData(
      icon: Icons.travel_explore_rounded,
      kicker: 'DISCOVER',
      prompt: AgentPromptSuggestions.discover,
    ),
    _PromptSuggestionData(
      icon: Icons.auto_awesome_rounded,
      kicker: 'TAILOR',
      prompt: AgentPromptSuggestions.tailor,
    ),
    _PromptSuggestionData(
      icon: Icons.mail_outline_rounded,
      kicker: 'OUTREACH',
      prompt: AgentPromptSuggestions.outreach,
    ),
    _PromptSuggestionData(
      icon: Icons.insights_rounded,
      kicker: 'STRATEGY',
      prompt: AgentPromptSuggestions.strategy,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppConstants.screenHorizontalPadding,
        ),
        itemCount: _items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          return _PromptSuggestionCard(data: _items[i])
              .animate(delay: (i * 70).ms)
              .fadeIn(duration: 320.ms)
              .moveY(begin: 12, end: 0, curve: Curves.easeOutCubic);
        },
      ),
    );
  }
}

class _PromptSuggestionData {
  const _PromptSuggestionData({
    required this.icon,
    required this.kicker,
    required this.prompt,
  });

  final IconData icon;
  final String kicker;
  final String prompt;
}

class _PromptSuggestionCard extends ConsumerWidget {
  const _PromptSuggestionCard({required this.data});

  final _PromptSuggestionData data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          // Hand the prompt to the chat composer rather than firing it — the
          // user lands on the chat with the prompt pre-filled, attaches a
          // resume, then taps Send themselves.
          ref.read(composerDraftProvider.notifier).state = data.prompt;
          context.go('${RouteNames.agentChat}?focus=1');
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 230,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: brand.border),
            boxShadow: [
              BoxShadow(
                color: brand.shadow,
                blurRadius: 28,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      // Lime box + black glyph: reads as a bright chip in both
                      // modes, and in dark mode it pops off the black backdrop.
                      color: brand.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(data.icon, color: brand.onAccent, size: 18),
                  ),
                  const Spacer(),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: brand.surfaceMuted,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.north_east_rounded,
                      size: 14,
                      color: brand.ink,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                data.kicker,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: brand.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                    data.prompt,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                      letterSpacing: 0.1,
                      height: 1.4,
                    ),
                  )
                  // A periodic on-brand glint sweeping across the prompt — a
                  // subtle premium "shine". Plays once, waits, repeats; gated
                  // on the OS reduce-motion setting like the app's other loops.
                  .animate(
                    onPlay: shouldAnimate(context)
                        ? (controller) => controller.repeat(period: 3200.ms)
                        : null,
                  )
                  .shimmer(duration: 1500.ms, color: brand.accent, angle: 0.5),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashboard "Ask Syncra" bar. Deliberately *not* an editable field — tapping
/// anywhere on it jumps straight to the chat page with the composer focused.
/// Typing (and the conversation's history) lives entirely on the chat page, so
/// the user never has to wonder where the chatbot is. The label echoes the
/// latest chat turn so the bar reads as a continuation of the conversation.
class _AgentInputBar extends ConsumerWidget {
  const _AgentInputBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final items = ref.watch(agentChatProvider.select((s) => s.items));
    final label = _lastTurnLabel(items) ?? 'Chat with Syncra';
    return Semantics(
      button: true,
      label: 'Ask Syncra — opens chat',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.go('${RouteNames.agentChat}?focus=1'),
          borderRadius: BorderRadius.circular(28),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: brand.glassFill,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: brand.glassBorder),
              boxShadow: [
                BoxShadow(
                  color: brand.shadow,
                  blurRadius: 40,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Row(
              children: [
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: brand.textSoft,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: brand.ink,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: brand.inkInverse,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _lastTurnLabel(List<ChatItem> items) {
    for (final item in items.reversed) {
      if (item is UserMessage) {
        final text = item.text.trim();
        if (text.isNotEmpty) return text;
      } else if (item is AgentTurn) {
        final text = _firstTextFromBlocks(item.blocks);
        if (text != null && text.isNotEmpty) return text;
      }
    }
    return null;
  }

  String? _firstTextFromBlocks(List<AgentBlock> blocks) {
    for (final block in blocks) {
      if (block is TextBlock) {
        final t = block.text.trim();
        if (t.isNotEmpty) return t;
      }
    }
    return null;
  }
}
