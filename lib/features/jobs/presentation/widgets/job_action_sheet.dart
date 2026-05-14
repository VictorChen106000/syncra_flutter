import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/models/job.dart';
import '../../state/jobs_controller.dart';

class JobActionSheet {
  const JobActionSheet._();

  static Future<void> show(BuildContext context, Job job) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _JobActionSheetBody(job: job),
    );
  }
}

class _JobActionSheetBody extends StatelessWidget {
  const _JobActionSheetBody({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<JobsController>();
    final isSaved = controller.isSaved(job.id);
    final isHidden = controller.isHidden(job.id);
    final label = '${job.title} at ${job.company}';

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _ActionTile(
              icon: isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              label: isSaved ? 'Saved' : 'Save for later',
              onTap: () {
                controller.toggleSaved(job.id, label: label);
                Navigator.of(context).pop();
              },
            ),
            _ActionTile(
              icon: Icons.ios_share_rounded,
              label: 'Share',
              onTap: () async {
                Navigator.of(context).pop();
                await SharePlus.instance.share(
                  ShareParams(
                    text: '$label\n${job.location} · ${job.salary}',
                    subject: label,
                  ),
                );
              },
            ),
            _ActionTile(
              icon: isHidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              label: isHidden ? 'Show again' : 'Hide this role',
              onTap: () {
                if (isHidden) {
                  controller.unhide(job.id);
                } else {
                  controller.hide(job.id, label: label);
                }
                Navigator.of(context).pop();
              },
            ),
            _ActionTile(
              icon: Icons.close_rounded,
              label: 'Dismiss',
              destructive: true,
              onTap: () {
                controller.dismiss(job.id, label: label);
                Navigator.of(context).pop();
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.ink;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
