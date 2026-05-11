import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../data/mock/mock_notifications.dart';
import '../../../shared/animations/agent_pulse_icon.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../../shared/widgets/section_title.dart';
import '../../../shared/widgets/step_pill.dart';
import '../../auth/state/auth_controller.dart';
import '../../resumes/presentation/widgets/resume_attachment_chips.dart';
import '../../resumes/presentation/widgets/select_resumes_bottom_sheet.dart';
import '../../resumes/state/resume_controller.dart';
import 'widgets/agent_activity_feed.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScreen(
      showBottomNav: true,
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
                      20,
                      AppConstants.screenHorizontalPadding,
                      200,
                    ),
                    children: const [
                      _ApprovalPipelineCard(),
                      SizedBox(height: 28),
                      _RecentActivityHeader(),
                      AgentActivityFeed(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const _FloatingAgentInput(),
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
          avatar: _Avatar(initial: user?.initial ?? 'D'),
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
  const _Avatar({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.ink,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: AppColors.accent,
          fontWeight: FontWeight.w900,
          fontSize: 20,
        ),
      ),
    );
  }
}

class _AgentLiveBanner extends StatelessWidget {
  const _AgentLiveBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(alpha: 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(alpha: 0.10),
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .scale(
                      duration: 1500.ms,
                      begin: const Offset(0.85, 0.85),
                      end: const Offset(1.15, 1.15),
                      curve: Curves.easeInOut,
                    )
                    .fadeIn(),
                const AgentPulseIcon(size: 18),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppStrings.agentLive.toUpperCase(),
                  style: TextStyle(
                    color: AppColors.accent.withValues(alpha: 0.70),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  AppStrings.activeTask,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
          borderRadius: BorderRadius.circular(28),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => context.go(RouteNames.jobs),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(28),
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
                  const SizedBox(height: 18),
                  const Text(
                    AppStrings.reviewApplications,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: AppColors.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    AppStrings.reviewApplicationsBody,
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                      height: 1.5,
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
// Recent activity header
// ---------------------------------------------------------------------------

class _RecentActivityHeader extends StatelessWidget {
  const _RecentActivityHeader();

  @override
  Widget build(BuildContext context) {
    return const SectionTitle(title: AppStrings.recentActivity);
  }
}

// ---------------------------------------------------------------------------
// Floating AI input bar
// ---------------------------------------------------------------------------

class _FloatingAgentInput extends StatelessWidget {
  const _FloatingAgentInput();

  @override
  Widget build(BuildContext context) {
    return Consumer<ResumeController>(
      builder: (context, resumeController, _) {
        return Positioned(
          left: AppConstants.screenHorizontalPadding,
          right: AppConstants.screenHorizontalPadding,
          bottom: AppConstants.floatingInputBottom,
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
                    const SizedBox(width: 6),
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
          ),
        );
      },
    );
  }
}
