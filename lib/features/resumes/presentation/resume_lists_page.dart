import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';
import '../../../shared/widgets/app_back_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../state/resume_controller.dart';
import 'widgets/resume_upload_card.dart';

class ResumeListsPage extends StatefulWidget {
  const ResumeListsPage({super.key});

  @override
  State<ResumeListsPage> createState() => _ResumeListsPageState();
}

class _ResumeListsPageState extends State<ResumeListsPage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: SafeArea(
        bottom: false,
        child: Consumer<ResumeController>(
          builder: (context, controller, _) {
            final visibleResumes = _tabIndex == 0 ? controller.resumes : controller.tailoredResumes;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 24, 14),
                  child: Row(
                    children: [
                      AppBackButton(onPressed: () => context.go(RouteNames.login)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          AppStrings.resumeListsTitle,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.go(RouteNames.dashboard),
                        child: const Text('Skip'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppConstants.screenHorizontalPadding),
                  child: _TabSwitcher(
                    selectedIndex: _tabIndex,
                    onChanged: (value) => setState(() => _tabIndex = value),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 112),
                    children: [
                      if (_tabIndex == 0)
                        _UploadBox(onTap: controller.pickAndUploadResumes),
                      if (_tabIndex == 0) const SizedBox(height: 14),
                      ...controller.uploadQueue.map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ResumeUploadCard(uploadingItem: item),
                        ),
                      ),
                      if (visibleResumes.isEmpty && controller.uploadQueue.isEmpty)
                        const _EmptyResumeState(),
                      ...visibleResumes.map(
                        (resume) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ResumeUploadCard(
                            resume: resume,
                            onOpen: () {},
                            onDelete: _tabIndex == 0 ? () => controller.deleteResume(resume.id) : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 30),
                  child: FilledButton(
                    onPressed: () => context.go(RouteNames.dashboard),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: AppColors.ink,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    child: const Text('Continue to Home', style: TextStyle(fontWeight: FontWeight.w900)),
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
        color: AppColors.border.withOpacity( 0.40),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _TabButton(label: AppStrings.myUploads, active: selectedIndex == 0, onTap: () => onChanged(0)),
          _TabButton(label: AppStrings.aiTailored, active: selectedIndex == 1, onTap: () => onChanged(1)),
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
        duration: const Duration(milliseconds: 220),
        decoration: BoxDecoration(
          color: active ? AppColors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity( 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UploadBox extends StatelessWidget {
  const _UploadBox({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.ink.withOpacity( 0.30), width: 1.4),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.upload_rounded, size: 30),
            SizedBox(height: 8),
            Text(AppStrings.uploadResume, style: TextStyle(fontWeight: FontWeight.w900)),
            SizedBox(height: 4),
            Text(AppStrings.uploadResumeHint, style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _EmptyResumeState extends StatelessWidget {
  const _EmptyResumeState();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Column(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.ink,
            child: Icon(Icons.description_rounded, color: Colors.white),
          ),
          SizedBox(height: 14),
          Text(AppStrings.noResumesTitle, style: TextStyle(fontWeight: FontWeight.w900)),
          SizedBox(height: 8),
          Text(
            AppStrings.noResumesBody,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }
}
