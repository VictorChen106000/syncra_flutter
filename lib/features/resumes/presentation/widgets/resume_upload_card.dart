import 'package:flutter/material.dart';

import '../../../../core/theme/brand_theme.dart';
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
    final brand = context.brand;
    final name = resume?.name ?? uploadingItem!.name;
    final size = resume?.size ?? uploadingItem!.size;
    final progress = uploadingItem?.progress ?? 100;
    final progressFactor = (progress.clamp(0, 100) as num).toDouble() / 100;
    final hasError = uploadingItem?.hasError ?? false;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              color: hasError
                  ? brand.danger.withValues(alpha: 0.08)
                  : brand.surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: hasError
                    ? brand.danger.withValues(alpha: 0.4)
                    : brand.border,
              ),
              boxShadow: [
                BoxShadow(
                  color: brand.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          if (uploadingItem != null && !hasError)
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progressFactor,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: brand.accent.withValues(alpha: 0.18),
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
                    color: hasError ? brand.danger : brand.ink,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.description_rounded,
                    color: brand.inkInverse,
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
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: -0.2,
                          color: brand.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle(size, progress, hasError),
                        style: TextStyle(
                          color: brand.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (resume != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Uploaded ${DateFormatter.uploadDate(resume!.uploadedAt)}',
                            style: TextStyle(
                              color: brand.textSoft,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (resume != null && onOpen != null)
                  _ActionIconButton(
                    icon: Icons.visibility_outlined,
                    tooltip: 'Preview',
                    onTap: onOpen!,
                    color: brand.ink,
                  ),
                if (onDelete != null)
                  _ActionIconButton(
                    icon: Icons.delete_outline_rounded,
                    tooltip: 'Delete',
                    onTap: onDelete!,
                    color: brand.textMuted,
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

/// Bare glyph action — no chip, no circle. Just the icon in a 44px tap target
/// with a quiet ripple, so the file name stays the loudest thing on the row.
class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    required this.color,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 22,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(child: Icon(icon, size: 20, color: color)),
        ),
      ),
    );
  }
}
