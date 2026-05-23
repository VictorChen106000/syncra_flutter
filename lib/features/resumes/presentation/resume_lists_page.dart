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
              onBack: () => context.go(RouteNames.agentChat),
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
                  _UploadDropZone(onTap: notifier.pickAndUploadResumes),
                  for (final item in state.uploadQueue)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: ResumeUploadCard(uploadingItem: item),
                    ),
                  if (isEmpty) ...[
                    const SizedBox(height: 16),
                    EmptyStateCard(
                      icon: Icons.upload_rounded,
                      title: AppStrings.noResumesTitle,
                      body: AppStrings.noResumesBody,
                      actionLabel: 'Upload resume',
                      actionIcon: Icons.add_rounded,
                      onAction: notifier.pickAndUploadResumes,
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

class _UploadDropZone extends StatelessWidget {
  const _UploadDropZone({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 130,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: brand.ink.withValues(alpha: 0.30),
              width: 1.5,
              style: BorderStyle.solid,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.upload_rounded, size: 28, color: brand.ink),
              const SizedBox(height: 8),
              Text(
                AppStrings.uploadResume,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: brand.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppStrings.uploadResumeHint,
                style: TextStyle(
                  color: brand.textMuted,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
