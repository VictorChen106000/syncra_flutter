import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/animations/agent_pulse_icon.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_screen.dart';
import '../../../shared/widgets/notification_bell.dart';
import '../../../shared/widgets/section_title.dart';
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
          ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 180),
            children: const [
              _DashboardHeader(),
              SizedBox(height: 14),
              _AgentLiveBanner(),
              SizedBox(height: 30),
              _ApprovalPipelineCard(),
              SizedBox(height: 30),
              SectionTitle(title: AppStrings.agentThoughtStream),
              AgentActivityFeed(),
            ],
          ),
          const _FloatingAgentInput(),
        ],
      ),
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const CircleAvatar(
          radius: 24,
          backgroundColor: AppColors.ink,
          child: Text('D', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w900)),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Daryn', style: TextStyle(color: AppColors.ink, fontSize: 20, fontWeight: FontWeight.w900)),
              SizedBox(height: 3),
              Text(AppStrings.dashboardGreetingRole, style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w800)),
            ],
          ),
        ),
        const NotificationBell(),
      ],
    );
  }
}

class _AgentLiveBanner extends StatelessWidget {
  const _AgentLiveBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity( 0.10),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        children: [
          CircleAvatar(
            backgroundColor: Color(0x11111111),
            child: AgentPulseIcon(size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.agentLive, style: TextStyle(color: AppColors.accent, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1.3)),
                SizedBox(height: 2),
                Text(AppStrings.activeTask, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ApprovalPipelineCard extends StatelessWidget {
  const _ApprovalPipelineCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SectionTitle(
          title: AppStrings.approvalPipeline,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(99)),
            child: const Text('4 Pending', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
          ),
        ),
        AppCard(
          onTap: () {},
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: List.generate(
                        4,
                        (index) => Container(
                          margin: EdgeInsets.only(left: index == 0 ? 0 : 0),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: Center(
                            child: Text(['B', 'T', 'L', 'V'][index], style: const TextStyle(fontWeight: FontWeight.w900)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(AppStrings.reviewApplications, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    const Text(AppStrings.reviewApplicationsBody, style: TextStyle(color: AppColors.textMuted, height: 1.45, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
              const CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.ink,
                child: Icon(Icons.arrow_forward_rounded, color: AppColors.accent),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FloatingAgentInput extends StatelessWidget {
  const _FloatingAgentInput();

  @override
  Widget build(BuildContext context) {
    return Consumer<ResumeController>(
      builder: (context, resumeController, _) {
        return Positioned(
          left: AppConstants.screenHorizontalPadding,
          right: AppConstants.screenHorizontalPadding,
          bottom: 118,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity( 0.76),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.transparent, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity( 0.12),
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
                    IconButton(
                      onPressed: () => SelectResumesBottomSheet.show(context),
                      icon: const Icon(Icons.add_rounded),
                      style: IconButton.styleFrom(backgroundColor: AppColors.scaffold),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => context.go(RouteNames.agentChat),
                        child: const Text(
                          AppStrings.askSyncra,
                          style: TextStyle(color: AppColors.textSoft, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => context.go(RouteNames.agentChat),
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      style: IconButton.styleFrom(backgroundColor: AppColors.ink),
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
