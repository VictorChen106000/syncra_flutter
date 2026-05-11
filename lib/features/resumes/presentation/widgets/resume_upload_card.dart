import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/date_formatter.dart';
import '../../../../core/utils/file_formatter.dart';
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: hasError ? Colors.red.shade50 : AppColors.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: hasError ? Colors.red.shade200 : AppColors.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          if (uploadingItem != null && !hasError)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: FractionallySizedBox(
                widthFactor: progress / 100,
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.18),
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: hasError ? Colors.red : AppColors.ink,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.description_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle(size, progress, hasError),
                        style: const TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (resume != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Uploaded ${DateFormatter.uploadDate(resume!.uploadedAt)}',
                            style: const TextStyle(
                              color: AppColors.textSoft,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (resume != null && onOpen != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _ActionIconButton(
                      icon: Icons.search_rounded,
                      onTap: onOpen!,
                      bg: AppColors.surface,
                      hasBorder: true,
                    ),
                  ),
                if (onDelete != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _ActionIconButton(
                      icon: Icons.delete_outline_rounded,
                      onTap: onDelete!,
                      bg: AppColors.scaffold,
                      iconColor: AppColors.textMuted,
                    ),
                  ),
              ],
            ),
          ),
        ],
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

class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.onTap,
    required this.bg,
    this.iconColor = AppColors.ink,
    this.hasBorder = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color bg;
  final Color iconColor;
  final bool hasBorder;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: bg,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: hasBorder ? Border.all(color: AppColors.border) : null,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }
}
