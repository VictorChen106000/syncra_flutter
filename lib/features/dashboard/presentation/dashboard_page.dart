import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../data/mock/mock_notifications.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/step_pill.dart';
import '../../auth/state/auth_controller.dart';
import '../../agent_chat/state/agent_chat_controller.dart';
import '../../resumes/presentation/widgets/resume_attachment_chips.dart';
import '../../resumes/presentation/widgets/select_resumes_bottom_sheet.dart';
import '../../resumes/state/resume_controller.dart';

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
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppConstants.screenHorizontalPadding,
                      AppConstants.screenTopPadding,
                      AppConstants.screenHorizontalPadding,
                      320,
                    ),
                    children: const [
                      _ApprovalPipelineCard(),
                    ],
                  ),
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

class _DashboardHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<AuthController>(
      builder: (context, auth, _) {
        final user = auth.appUser;
        return AppHeader.home(
          avatar: _Avatar(photoUrl: user?.photoUrl),
          name: user?.displayName ?? 'Daryn',
          role: AppStrings.dashboardGreetingRole,
          unreadCount: MockNotifications.unreadCount,
          onBellTap: () => context.go(RouteNames.notifications),
          bottom: const _AgentLiveBanner(),
        );
      },
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
// Approval pipeline card
// ---------------------------------------------------------------------------

class _ApprovalPipelineCard extends StatelessWidget {
  const _ApprovalPipelineCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionTitle(
          title: AppStrings.approvalPipeline,
          trailing: const StepPill(label: '4 Pending', accent: true),
        ),
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppConstants.largeCardRadius),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppConstants.largeCardRadius),
            onTap: () => context.go(RouteNames.jobs),
            child: Container(
              padding: const EdgeInsets.all(AppConstants.cardPadding),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius:
                    BorderRadius.circular(AppConstants.largeCardRadius),
                border: Border.all(color: AppColors.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _OverlappingAvatars(initials: ['B', 'T', 'L', 'V']),
                      const Spacer(),
                      Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: AppColors.ink,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.arrow_forward_rounded,
                          color: AppColors.accent,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    AppStrings.reviewApplications,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                      letterSpacing: -0.2,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    AppStrings.reviewApplicationsBody,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                      height: 1.45,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OverlappingAvatars extends StatelessWidget {
  const _OverlappingAvatars({required this.initials});

  final List<String> initials;

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    const overlap = 10.0;
    final width = size + (initials.length - 1) * (size - overlap);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: List.generate(initials.length, (i) {
          return Positioned(
            left: i * (size - overlap),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                initials[i],
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: AppColors.ink,
                ),
              ),
            ),
          );
        }),
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
      prompt: 'Find UX roles at AI startups hiring this week',
    ),
    _PromptSuggestionData(
      icon: Icons.auto_awesome_rounded,
      kicker: 'TAILOR',
      prompt: 'Tailor my resume for the role I just saved',
    ),
    _PromptSuggestionData(
      icon: Icons.mail_outline_rounded,
      kicker: 'OUTREACH',
      prompt: 'Draft a cold outreach to the hiring manager',
    ),
    _PromptSuggestionData(
      icon: Icons.insights_rounded,
      kicker: 'STRATEGY',
      prompt: 'What roles match my current trajectory?',
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

class _PromptSuggestionCard extends StatelessWidget {
  const _PromptSuggestionCard({required this.data});

  final _PromptSuggestionData data;

  void _onTap(BuildContext context) {
    context.read<AgentChatController>().sendPrompt(prompt: data.prompt);
    context.go(RouteNames.agentChat);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onTap(context),
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

class _AgentInputBar extends StatelessWidget {
  const _AgentInputBar();

  @override
  Widget build(BuildContext context) {
    return Consumer<ResumeController>(
      builder: (context, resumeController, _) {
        return Container(
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
                resumes: resumeController.selectedResumes,
                onRemove: resumeController.removeSelectedResume,
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
                    child: GestureDetector(
                      onTap: () => context.go(RouteNames.agentChat),
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          resumeController.selectedResumes.isNotEmpty
                              ? AppStrings.askAgentAboutContext
                              : AppStrings.askSyncra,
                          style: const TextStyle(
                            color: AppColors.textSoft,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                  ),
                  InkResponse(
                    onTap: () => context.go(RouteNames.agentChat),
                    radius: 24,
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.ink,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
