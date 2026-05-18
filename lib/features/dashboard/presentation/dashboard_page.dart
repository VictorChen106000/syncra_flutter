import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../fixtures/mock_agent_service.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../agent/state/passive_agent_notifier.dart';
import '../../auth/state/auth_notifier.dart';
import '../../auth/state/user_profile_notifier.dart';
import '../../agent_chat/models/chat_message.dart';
import '../../agent_chat/state/agent_chat_notifier.dart';
import '../../notifications/state/notifications_notifier.dart';
import '../../resumes/presentation/widgets/resume_attachment_chips.dart';
import '../../resumes/presentation/widgets/select_resumes_bottom_sheet.dart';
import '../../resumes/state/resume_notifier.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      showBottomNav: false,
      activeTab: BottomNavTab.home,
      extendBehindBottomNav: true,
      child: Stack(
        children: [
          Positioned.fill(
            child: Column(
              children: [
                _DashboardHeader(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppConstants.screenHorizontalPadding,
                    AppConstants.screenTopPadding,
                    AppConstants.screenHorizontalPadding,
                    0,
                  ),
                  child: _AgentCardStack(),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppConstants.screenHorizontalPadding,
                    16,
                    AppConstants.screenHorizontalPadding,
                    0,
                  ),
                  child: _RunBriefCta(),
                ),
              ],
            ),
          ),
          const _FloatingAgentArea(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sticky header — avatar + name + bell, agent live banner sits below as bottom slot
// ---------------------------------------------------------------------------

class _DashboardHeader extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final notifications = ref.watch(notificationsProvider);
    final user = auth.appUser;
    return AppHeader.home(
      avatar: _Avatar(photoUrl: user?.photoUrl),
      name: user?.displayName ?? 'Daryn',
      role: AppStrings.dashboardGreetingRole,
      unreadCount: notifications.unreadCount,
      onBellTap: () => context.go(RouteNames.notifications),
      bottom: const _AgentLiveBanner(),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.photoUrl});

  final String? photoUrl;

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
        shape: BoxShape.circle,
        color: AppColors.ink,
        border: Border.all(color: Colors.white, width: 2),
        image: DecorationImage(
          image: image,
          fit: BoxFit.cover,
          onError: (_, _) {},
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
    );
  }
}

class _AgentLiveBanner extends StatelessWidget {
  const _AgentLiveBanner();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _LiveDot(),
        const SizedBox(width: 8),
        Text(
          AppStrings.agentLive.toUpperCase(),
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.textMuted.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppStrings.activeTask,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 8,
      height: 8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.accentBright.withValues(alpha: 0.55),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .scale(
                duration: 1400.ms,
                begin: const Offset(0.6, 0.6),
                end: const Offset(1.8, 1.8),
                curve: Curves.easeOut,
              )
              .fadeOut(duration: 1400.ms),
          Container(
            width: 6,
            height: 6,
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
// Agent fan-stack — Brief Ready + Approval Pipeline + Strategic, tappable
// ---------------------------------------------------------------------------

class _AgentCardStack extends ConsumerStatefulWidget {
  const _AgentCardStack();

  @override
  ConsumerState<_AgentCardStack> createState() => _AgentCardStackState();
}

class _AgentCardStackState extends ConsumerState<_AgentCardStack> {
  static const double _maxCardWidth = 320;
  static const double _cardHeight = 180;
  static const double _stackHeight = 270;
  static const double _cardLeftInset = 6;
  // Right-side breathing room reserved for the fanned second card so it never
  // crosses the screen edge.
  static const double _fanRightMargin = 44;
  static const Duration _animDuration = Duration(milliseconds: 550);

  bool _expanded = false;
  bool _prevExpanded = false;
  final List<int> _order = [0, 1];
  List<int> _prevOrder = [0, 1];
  int _version = 0;

  void _animate(VoidCallback mutate) {
    setState(() {
      _prevExpanded = _expanded;
      _prevOrder = List<int>.from(_order);
      mutate();
      _version++;
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
    final passive = ref.watch(passiveAgentProvider);
    final cards = <_StackCardData>[
      _StackCardData(
        title: 'Brief Ready',
        kicker: 'Passive Agent',
        count: passive.readyCount,
        background: AppColors.accent,
        foreground: AppColors.ink,
        icon: Icons.bolt_rounded,
        route: RouteNames.jobs,
      ),
      _StackCardData(
        title: 'Approval Pipeline',
        kicker: 'Pending Review',
        count: 4,
        background: AppColors.surface,
        foreground: AppColors.ink,
        icon: Icons.work_outline_rounded,
        route: RouteNames.jobs,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 14),
          child: Text(
            _expanded
                ? 'TAP A CARD TO BRING IT FRONT · TAP FRONT TO COLLAPSE'
                : 'TAP THE STACK TO POP OUT',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
              color: AppColors.textMuted,
            ),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _expanded ? _onOutsideTap : null,
          child: SizedBox(
                height: _stackHeight,
                width: double.infinity,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth = math.min(
                      _maxCardWidth,
                      constraints.maxWidth -
                          _cardLeftInset -
                          _fanRightMargin,
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
              )
              .animate()
              .shake(
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

  Widget _buildCard(_StackCardData data, int cardIdx, double t, double cardWidth) {
    final prevSlot = _prevOrder.indexOf(cardIdx).toDouble();
    final newSlot = _order.indexOf(cardIdx).toDouble();
    final slot = _lerp(prevSlot, newSlot, t);

    final prevExpand = _prevExpanded ? 1.0 : 0.0;
    final newExpand = _expanded ? 1.0 : 0.0;
    final expand = _lerp(prevExpand, newExpand, t);

    // Collapsed: tight stack, second card peeks bottom-right with a small tilt.
    final collapsedRot = slot * 6.0;
    final collapsedX = slot * 16.0;
    final collapsedY = slot * 14.0;

    // Expanded: fan to the right and down — the second card splays sideways
    // and drops so its kicker/title shows below the front card's top edge.
    final expandedRot = -4.0 + slot * 10.0;
    final expandedX = slot * 36.0;
    final expandedY = slot * 32.0;

    final rotDeg = _lerp(collapsedRot, expandedRot, expand);
    final tx = _lerp(collapsedX, expandedX, expand);
    final ty = _lerp(collapsedY, expandedY, expand);

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
    required this.count,
    required this.background,
    required this.foreground,
    required this.icon,
    required this.route,
  });

  final String title;
  final String kicker;
  final int count;
  final Color background;
  final Color foreground;
  final IconData icon;
  final String route;
}

class _StackCard extends StatelessWidget {
  const _StackCard({
    required this.data,
    required this.width,
    required this.height,
    required this.showAction,
  });

  final _StackCardData data;
  final double width;
  final double height;
  final bool showAction;

  @override
  Widget build(BuildContext context) {
    final fg = data.foreground;
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: data.background,
        borderRadius: BorderRadius.circular(AppConstants.largeCardRadius),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
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
                        color: fg.withValues(alpha: 0.6),
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
                child: Text(
                  data.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                    height: 1.05,
                    color: fg,
                  ),
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

// ---------------------------------------------------------------------------
// Run today's brief — user-initiated CTA. The morning brief no longer
// auto-fires; this is the only way it runs.
// ---------------------------------------------------------------------------

class _RunBriefCta extends ConsumerWidget {
  const _RunBriefCta();

  String _relativeTime(DateTime then) {
    final delta = DateTime.now().difference(then);
    if (delta.inMinutes < 1) return 'just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    return '${delta.inDays}d ago';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gate on the user's opt-in setting (Settings → "Today's brief").
    // Default false: brand-new accounts see nothing until they enable it,
    // matching the "opt-in, never auto-fires" contract.
    final enabled =
        ref.watch(userProfileProvider)?.morningBriefEnabled ?? false;
    if (!enabled) return const SizedBox.shrink();

    final state = ref.watch(passiveAgentProvider);
    final running = state.isRunning;
    final lastBrief = state.lastBriefAt;

    final subtitle = running
        ? 'Scanning roles and scoring matches…'
        : lastBrief == null
            ? 'Tap to scan for fresh roles matching your profile.'
            : 'Last brief ${_relativeTime(lastBrief)} · '
                '${state.readyCount} ready · ${state.inputNeededCount} need input';

    return Container(
      padding: const EdgeInsets.all(AppConstants.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.cardRadius),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.bolt_rounded,
              color: AppColors.accent,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Run today's brief",
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: AppColors.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: running ? AppColors.softSurface : AppColors.ink,
              foregroundColor: running ? AppColors.textMuted : Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: running
                ? null
                : () => ref.read(passiveAgentProvider.notifier).runBrief(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (running)
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.ink,
                    ),
                  )
                else
                  const Icon(Icons.play_arrow_rounded, size: 16),
                const SizedBox(width: 6),
                Text(
                  running ? 'Running' : 'Run',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
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
// Floating agent area — prompt preview cards stacked above the input bar
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Prompt suggestion preview cards
// ---------------------------------------------------------------------------

class _PromptSuggestions extends StatelessWidget {
  const _PromptSuggestions();

  static const _items = <_PromptSuggestionData>[
    _PromptSuggestionData(
      icon: Icons.travel_explore_rounded,
      kicker: 'DISCOVER',
      prompt: MockAgentService.discoverPrompt,
    ),
    _PromptSuggestionData(
      icon: Icons.auto_awesome_rounded,
      kicker: 'TAILOR',
      prompt: MockAgentService.tailorPrompt,
    ),
    _PromptSuggestionData(
      icon: Icons.mail_outline_rounded,
      kicker: 'OUTREACH',
      prompt: MockAgentService.outreachPrompt,
    ),
    _PromptSuggestionData(
      icon: Icons.insights_rounded,
      kicker: 'STRATEGY',
      prompt: MockAgentService.strategyPrompt,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          ref.read(agentChatProvider.notifier).sendPrompt(prompt: data.prompt);
          context.go(RouteNames.agentChat);
        },
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 230,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
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
                      color: AppColors.ink,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      data.icon,
                      color: AppColors.accent,
                      size: 18,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: AppColors.scaffold,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.north_east_rounded,
                      size: 14,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Text(
                data.kicker,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                data.prompt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                  letterSpacing: -0.2,
                  height: 1.35,
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
// Glass AI input bar
// ---------------------------------------------------------------------------

class _AgentInputBar extends ConsumerStatefulWidget {
  const _AgentInputBar();

  @override
  ConsumerState<_AgentInputBar> createState() => _AgentInputBarState();
}

class _AgentInputBarState extends ConsumerState<_AgentInputBar>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 11,
  );

  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _bounceController;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController.unbounded(
      vsync: this,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _bounce() {
    _bounceController.stop();
    _bounceController.value = 0.94;
    _bounceController.animateWith(
      SpringSimulation(_spring, 0.94, 1.0, 0),
    );
  }

  void _send() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final selected = ref.read(resumeProvider).selectedResumes;
    final attachments = selected
        .map((r) => ChatAttachment(id: r.id, name: r.name))
        .toList();

    ref.read(agentChatProvider.notifier).sendPrompt(
          prompt: text,
          attachments: attachments,
        );
    _textController.clear();
    _focusNode.unfocus();

    HapticFeedback.lightImpact();
    _bounce();
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      context.go(RouteNames.agentChat);
    });
  }

  @override
  Widget build(BuildContext context) {
    final resumeState = ref.watch(resumeProvider);
    final resumeNotifier = ref.read(resumeProvider.notifier);
    final hasText = _textController.text.trim().isNotEmpty;
    return AnimatedBuilder(
      animation: _bounceController,
      builder: (context, child) => Transform.scale(
        scale: _bounceController.value,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.40),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 40,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ResumeAttachmentChips(
              resumes: resumeState.selectedResumes,
              onRemove: resumeNotifier.removeSelectedResume,
            ),
            Row(
              children: [
                InkResponse(
                  onTap: () => SelectResumesBottomSheet.show(context),
                  radius: 24,
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.scaffold,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.add_rounded,
                      color: AppColors.ink,
                      size: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                    style: const TextStyle(
                      color: AppColors.ink,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: resumeState.selectedResumes.isNotEmpty
                          ? AppStrings.askAgentAboutContext
                          : AppStrings.askSyncra,
                      hintStyle: const TextStyle(
                        color: AppColors.textSoft,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      isCollapsed: true,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
                InkResponse(
                  onTap: hasText ? _send : null,
                  radius: 24,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: hasText ? AppColors.ink : AppColors.scaffold,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.send_rounded,
                      color: hasText ? Colors.white : AppColors.textSoft,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
