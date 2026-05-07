import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/file_formatter.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../models/resume_file.dart';
import '../../models/upload_queue_item.dart';

class ResumeUploadCard extends StatelessWidget {
  const ResumeUploadCard({
    super.key,
    this.resume,
    this.uploadingItem,
    this.onOpen,
    this.onDelete,
  }) : assert(resume != null || uploadingItem != null);

  final ResumeFile? resume;
  final UploadQueueItem? uploadingItem;
  final VoidCallback? onOpen;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final name = resume?.name ?? uploadingItem!.name;
    final size = resume?.size ?? uploadingItem!.size;
    final progress = uploadingItem?.progress ?? 100;
    final hasError = uploadingItem?.hasError ?? false;

    return AppCard(
      padding: EdgeInsets.zero,
      backgroundColor: hasError ? Colors.red.shade50 : AppColors.surface,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            if (uploadingItem != null && !hasError)
              Positioned.fill(
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress / 100,
                  child: ColoredBox(color: AppColors.accent.withOpacity( 0.20)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: hasError ? Colors.red : AppColors.ink,
                    child: const Icon(Icons.description_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(
                          _subtitle(size, progress, hasError),
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                        if (resume != null)
                          Text(
                            'Uploaded ${DateFormatter.uploadDate(resume!.uploadedAt)}',
                            style: const TextStyle(color: AppColors.textSoft, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  if (resume != null && onOpen != null)
                    IconButton(
                      onPressed: onOpen,
                      icon: const Icon(Icons.search_rounded),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.surface,
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                  if (resume != null && onDelete != null)
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                      color: AppColors.textMuted,
                      style: IconButton.styleFrom(backgroundColor: AppColors.scaffold),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(int size, int progress, bool hasError) {
    if (hasError) return 'Error';
    if (uploadingItem != null && progress < 100) {
      return '${FileFormatter.size(size)} • $progress%';
    }
    return FileFormatter.size(size);
  }
}
