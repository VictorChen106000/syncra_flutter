import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/file_formatter.dart';
import '../../models/resume_file.dart';

class ResumeAttachmentChips extends StatelessWidget {
  const ResumeAttachmentChips({
    super.key,
    required this.resumes,
    required this.onRemove,
  });

  final List<ResumeFile> resumes;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    if (resumes.isEmpty) return const SizedBox.shrink();

    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(left: 4, right: 4, bottom: 4),
          itemCount: resumes.length,
          separatorBuilder: (context, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final resume = resumes[index];
            return Container(
              constraints: const BoxConstraints(maxWidth: 170),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.accent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.description_rounded, size: 15, color: AppColors.ink),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      FileFormatter.cleanName(resume.name),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => onRemove(resume.id),
                    child: const Icon(Icons.close_rounded, size: 15, color: AppColors.textMuted),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
