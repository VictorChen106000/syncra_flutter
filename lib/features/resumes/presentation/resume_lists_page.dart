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
import '../models/resume_file.dart';
import '../state/resume_notifier.dart';
import 'widgets/resume_upload_card.dart';

class ResumeListsPage extends ConsumerStatefulWidget {
  const ResumeListsPage({super.key});

  @override
  ConsumerState<ResumeListsPage> createState() => _ResumeListsPageState();
}

class _ResumeListsPageState extends ConsumerState<ResumeListsPage> {
  int _tabIndex = 0;

  void _openPreview(ResumeFile resume) {
    context.go(RouteNames.resumePreview, extra: resume);
  }

  @override
  Widget build(BuildContext context) {
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
    final visibleResumes =
        _tabIndex == 0 ? state.resumes : state.tailoredResumes;

    return Scaffold(
      backgroundColor: brand.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
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
                        onTap: notifier.pickAndUploadResumes,
                      ),
                      const SizedBox(height: 14),
                    ],
                    for (final item in state.uploadQueue)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ResumeUploadCard(uploadingItem: item),
                      ),
                    if (visibleResumes.isEmpty && state.uploadQueue.isEmpty)
                      _tabIndex == 0
                          ? EmptyStateCard(
                              icon: Icons.upload_rounded,
                              title: AppStrings.noResumesTitle,
                              body: AppStrings.noResumesBody,
                              actionLabel: 'Upload resume',
                              actionIcon: Icons.add_rounded,
                              onAction: notifier.pickAndUploadResumes,
                            )
                          : EmptyStateCard(
                              icon: Icons.auto_awesome_rounded,
                              title: AppStrings.noTailoredTitle,
                              body: AppStrings.noTailoredBody,
                              actionLabel: 'Open chat',
                              onAction: () =>
                                  context.go(RouteNames.agentChat),
                            ),
                    for (final resume in visibleResumes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ResumeUploadCard(
                          resume: resume,
                          onOpen: () => _openPreview(resume),
                          onDelete: _tabIndex == 0
                              ? () => notifier.deleteResume(resume.id)
                              : null,
                        )
                            .animate()
                            .fadeIn(duration: 220.ms)
                            .moveY(begin: 8, end: 0),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabSwitcher extends StatelessWidget {
  const _TabSwitcher({
    required this.selectedIndex,
    required this.onChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: brand.border.withValues(alpha: 0.40),
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
    final brand = context.brand;
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: active ? brand.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: brand.shadow,
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
                  color: active ? brand.ink : brand.textMuted,
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
