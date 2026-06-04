import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../core/utils/motion.dart';
import '../../agent_chat/agent_prompt_suggestions.dart';
import '../../agent_chat/models/agent_block.dart';
import '../../agent_chat/models/chat_message.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../../shared/widgets/gooey_orb.dart';
import '../../agent/state/passive_agent_notifier.dart';
import '../../agent_chat/state/agent_chat_notifier.dart';
import '../../jobs/state/jobs_notifier.dart';
import '../../auth/state/auth_notifier.dart';
import '../../auth/state/user_profile_notifier.dart';
import '../../notifications/presentation/notifications_drawer.dart';
import '../../notifications/state/notifications_notifier.dart';
import 'widgets/agent_activity_timeline.dart';

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
// Agent hero area — a timeline of what the agent has done, with a gooey-orb
// greeting before the agent has surfaced anything.
// ---------------------------------------------------------------------------

/// Picks the dashboard hero: the agent-activity timeline once the agent has
/// done (or is doing) something, otherwise the warm gooey-orb empty state.
/// The timeline itself reads its individual milestones (matches, tailored
/// résumés, learned facts, drafted applications); here we only decide whether
/// there is *anything* to show yet.
class _AgentSection extends ConsumerWidget {
  const _AgentSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMatches = ref.watch(
      jobsProvider.select((s) => s.cards.isNotEmpty),
    );
    final agentActive = ref.watch(
      passiveAgentProvider.select(
        (s) => s.isRunning || s.lastBriefAt != null || s.activity.isNotEmpty,
      ),
    );
    if (hasMatches || agentActive) return const AgentActivityTimeline();
    return const _DashboardAgentEmptyState();
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
