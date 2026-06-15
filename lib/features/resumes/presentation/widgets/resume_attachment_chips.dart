import 'package:flutter/material.dart';

import '../../../../core/theme/brand_theme.dart';
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
    final brand = context.brand;
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
                color: brand.accent.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: brand.accent),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.description_rounded, size: 15, color: brand.ink),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      FileFormatter.cleanName(resume.name),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: brand.ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => onRemove(resume.id),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: brand.textMuted,
                    ),
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
