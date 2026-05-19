import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../state/resume_notifier.dart';
import 'resume_upload_card.dart';

class SelectResumesBottomSheet extends ConsumerWidget {
  const SelectResumesBottomSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.brand.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      builder: (_) => const SelectResumesBottomSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final state = ref.watch(resumeProvider);
    final notifier = ref.read(resumeProvider.notifier);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.88,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Resumes',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: brand.ink,
                          ),
                        ),
                        Text(
                          '${state.selectedResumeIds.length}/10 selected',
                          style: TextStyle(
                            color: brand.textMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: brand.ink),
                    style: IconButton.styleFrom(backgroundColor: brand.border),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: brand.border),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                children: [
                  InkWell(
                    onTap: notifier.pickAndUploadResumes,
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: brand.ink.withValues(alpha: 0.28),
                        ),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: brand.surfaceMuted,
                            child: Icon(Icons.upload_rounded, color: brand.ink),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Upload New Resume',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: brand.ink,
                                  ),
                                ),
                                Text(
                                  'PDF, DOC up to 5MB • Max 10 at once',
                                  style: TextStyle(
                                    color: brand.textMuted,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...state.uploadQueue.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ResumeUploadCard(uploadingItem: item),
                      )),
                  ...state.resumes.map((resume) {
                    final selected =
                        state.selectedResumeIds.contains(resume.id);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () => notifier.toggleSelectedResume(resume.id),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: brand.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: selected ? brand.ink : brand.border,
                              width: selected ? 1.4 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: selected
                                    ? brand.ink
                                    : brand.surfaceMuted,
                                child: Icon(
                                  Icons.description_rounded,
                                  color: selected
                                      ? brand.inkInverse
                                      : brand.ink,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Text(
                                  resume.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: brand.ink,
                                  ),
                                ),
                              ),
                              if (selected)
                                Icon(Icons.check_circle_rounded,
                                    color: brand.accent),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
