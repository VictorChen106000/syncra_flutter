import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/widgets/app_header.dart';
import '../models/resume_file.dart';
import '../state/resume_controller.dart';
import 'widgets/resume_upload_card.dart';

class ResumeListsPage extends StatefulWidget {
  const ResumeListsPage({super.key});

  @override
  State<ResumeListsPage> createState() => _ResumeListsPageState();
}

class _ResumeListsPageState extends State<ResumeListsPage> {
  int _tabIndex = 0;

  void _openPreview(ResumeFile resume) {
    context.go(RouteNames.resumePreview, extra: resume);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: Consumer<ResumeController>(
          builder: (context, controller, _) {
            final visibleResumes = _tabIndex == 0
                ? controller.resumes
                : controller.tailoredResumes;

            return Column(
              children: [
                AppHeader.page(
                  title: AppStrings.resumeListsTitle,
                  onBack: () => context.go(RouteNames.profile),
                  bottom: _TabSwitcher(
                    selectedIndex: _tabIndex,
                    onChanged: (i) => setState(() => _tabIndex = i),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: ListView(
                      key: ValueKey(_tabIndex),
                      padding: const EdgeInsets.fromLTRB(
                        AppConstants.screenHorizontalPadding,
                        20,
                        AppConstants.screenHorizontalPadding,
                        36,
                      ),
                      children: [
                        if (_tabIndex == 0) ...[
                          _UploadDropZone(
                            onTap: controller.pickAndUploadResumes,
                          ),
                          const SizedBox(height: 14),
                        ],
                        for (final item in controller.uploadQueue)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ResumeUploadCard(uploadingItem: item),
                          ),
                        if (visibleResumes.isEmpty &&
                            controller.uploadQueue.isEmpty)
                          _EmptyState(isUploads: _tabIndex == 0),
                        for (final resume in visibleResumes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ResumeUploadCard(
                              resume: resume,
                              onOpen: () => _openPreview(resume),
                              onDelete: _tabIndex == 0
                                  ? () => controller.deleteResume(resume.id)
                                  : null,
                            ).animate().fadeIn(duration: 220.ms).moveY(begin: 8, end: 0),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tab switcher
// ---------------------------------------------------------------------------

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.border.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _TabButton(
            label: AppStrings.myUploads,
            active: selectedIndex == 0,
            onTap: () => onChanged(0),
          ),
          _TabButton(
            label: AppStrings.aiTailored,
            active: selectedIndex == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active ? AppColors.ink : AppColors.textMuted,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Upload drop zone
// ---------------------------------------------------------------------------

class _UploadDropZone extends StatelessWidget {
  const _UploadDropZone({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 130,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppColors.ink.withValues(alpha: 0.30),
              width: 1.5,
              style: BorderStyle.solid,
            ),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.upload_rounded, size: 28, color: AppColors.ink),
              SizedBox(height: 8),
              Text(
                AppStrings.uploadResume,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: AppColors.ink,
                ),
              ),
              SizedBox(height: 4),
              Text(
                AppStrings.uploadResumeHint,
                style: TextStyle(
                  color: AppColors.textMuted,
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

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isUploads});

  final bool isUploads;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.description_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isUploads ? AppStrings.noResumesTitle : AppStrings.noTailoredTitle,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isUploads ? AppStrings.noResumesBody : AppStrings.noTailoredBody,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
