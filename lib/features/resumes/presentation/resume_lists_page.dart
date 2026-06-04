import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../core/theme/brand_theme.dart';
import '../../../shared/widgets/app_header.dart';
import '../../../shared/widgets/empty_state_card.dart';
import '../../../shared/widgets/section_title.dart';
import '../../agent_chat/state/agent_chat_notifier.dart';
import '../models/resume_file.dart';
import '../state/resume_notifier.dart';
import 'widgets/resume_upload_card.dart';

class ResumeListsPage extends ConsumerWidget {
  const ResumeListsPage({super.key});

  void _openPreview(BuildContext context, ResumeFile resume) {
    context.go(RouteNames.resumePreview, extra: resume);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    ref.listen<ResumeState>(resumeProvider, (prev, next) {
      final result = next.lastAction;
      if (result == null || result == prev?.lastAction) return;
      ref.read(resumeProvider.notifier).consumeLastAction();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            backgroundColor: result.isError ? brand.danger : null,
            content: Text(result.message),
          ),
        );
    });

    final state = ref.watch(resumeProvider);
    final notifier = ref.read(resumeProvider.notifier);
    final uploads = state.resumes;
    final tailored = state.tailoredResumes;
    final isEmpty =
        uploads.isEmpty && tailored.isEmpty && state.uploadQueue.isEmpty;

    return Scaffold(
      backgroundColor: brand.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            AppHeader.page(
              title: AppStrings.resumeListsTitle,
              onBack: () => context.go(RouteNames.profile),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppConstants.screenHorizontalPadding,
                  16,
                  AppConstants.screenHorizontalPadding,
                  36,
                ),
                children: [
                  _TopActions(
                    onUpload: notifier.pickAndUploadResumes,
                    onBuild: () {
                      ref.read(agentChatProvider.notifier).sendPrompt(
                            prompt: 'Help me build a resume from scratch.',
                          );
                      context.go(RouteNames.agentChat);
                    },
                  ),
                  for (final item in state.uploadQueue)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: ResumeUploadCard(uploadingItem: item),
                    ),
                  if (isEmpty) ...[
                    const SizedBox(height: 20),
                    const EmptyStateCard(
                      icon: Icons.upload_file_rounded,
                      title: AppStrings.noResumesTitle,
                      body: AppStrings.noResumesBody,
                    ),
                  ] else ...[
                    if (uploads.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      const SectionTitle(title: 'Your uploads'),
                      for (final r in uploads)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ResumeUploadCard(
                            resume: r,
                            onOpen: () => _openPreview(context, r),
                            onDelete: () => notifier.deleteResume(r.id),
                          )
                              .animate()
                              .fadeIn(duration: 220.ms)
                              .moveY(begin: 8, end: 0),
                        ),
                    ],
                    if (tailored.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const SectionTitle(title: 'Agent-tailored'),
                      for (final r in tailored)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ResumeUploadCard(
                            resume: r,
                            onOpen: () => _openPreview(context, r),
                          )
                              .animate()
                              .fadeIn(duration: 220.ms)
                              .moveY(begin: 8, end: 0),
                        ),
                    ] else if (uploads.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const SectionTitle(title: 'Agent-tailored'),
                      EmptyStateCard(
                        icon: Icons.auto_awesome_rounded,
                        title: AppStrings.noTailoredTitle,
                        body: AppStrings.noTailoredBody,
                        actionLabel: 'Open chat',
                        onAction: () => context.go(RouteNames.agentChat),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two primary entry points, side by side: upload an existing file, or hand
/// the job to the agent's from-scratch builder (seeds a goal prompt into chat
/// then routes there to run the `build_resume` flow). Kept to two short labels
/// — the heavy lifting is explained in the chat, not on a card.
class _TopActions extends StatelessWidget {
  const _TopActions({required this.onUpload, required this.onBuild});

  final VoidCallback onUpload;
  final VoidCallback onBuild;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.file_upload_outlined,
            label: 'Upload',
            onTap: onUpload,
            filled: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _ActionButton(
            icon: Icons.auto_awesome_rounded,
            label: 'Build with AI',
            onTap: onBuild,
            filled: false,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.filled,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Filled = solid ink hero (Upload). Otherwise an outlined surface with a
  /// lime accent glyph (Build with AI).
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final fg = filled ? brand.inkInverse : brand.ink;
    return Material(
      color: filled ? brand.ink : brand.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: filled ? null : Border.all(color: brand.border),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: filled ? fg : brand.accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: -0.2,
                    color: fg,
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
