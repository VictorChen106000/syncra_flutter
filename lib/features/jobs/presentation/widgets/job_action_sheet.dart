import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../../../data/models/job.dart';
import '../../../email/presentation/email_review_page.dart';
import '../../../email/services/recipient_resolver.dart';
import '../../state/jobs_notifier.dart';
import '../../services/job_trust_guard.dart';

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

class _JobActionSheetBody extends ConsumerWidget {
  const _JobActionSheetBody({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final state = ref.watch(jobsProvider);
    final notifier = ref.read(jobsProvider.notifier);
    final isSaved = state.isSaved(job.id);
    final isHidden = state.isHidden(job.id);
    final label = '${job.title} at ${job.company}';
    final trust = evaluateJobTrust(job);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: brand.border),
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
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: brand.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _TrustGuardPreflight(result: trust),
            _ActionTile(
              icon: Icons.drafts_outlined,
              label: 'Draft application email',
              onTap: () => _draftEmail(context, job),
            ),
            _ActionTile(
              icon: isSaved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              label: isSaved ? 'Saved' : 'Save for later',
              onTap: () {
                notifier.toggleSaved(job.id, label: label);
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
                  notifier.unhide(job.id);
                } else {
                  notifier.hide(job.id, label: label);
                }
                Navigator.of(context).pop();
              },
            ),
            _ActionTile(
              icon: Icons.close_rounded,
              label: 'Dismiss',
              destructive: true,
              onTap: () {
                notifier.dismiss(job.id, label: label);
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

Future<bool?> _confirmTrustGuardProceed(
  BuildContext context,
  JobTrustGuardResult trust,
) {
  final brand = context.brand;

  return showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: brand.surface,
        title: Text(
          '${trust.riskLabel} detected',
          style: TextStyle(color: brand.ink, fontWeight: FontWeight.w900),
        ),
        content: Text(
          '${trust.safeNextStep}\n\nContinue drafting anyway?',
          style: TextStyle(color: brand.textMuted, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Draft anyway'),
          ),
        ],
      );
    },
  );
}

/// Opens the email review sheet pre-filled with a starter draft for [job],
/// then saves it to the user's Gmail Drafts (nothing is sent). The recipient
/// is a best-effort guess the user confirms in the sheet.
Future<void> _draftEmail(BuildContext context, Job job) async {
  final trust = evaluateJobTrust(job);

  if (trust.needsVerification) {
    final confirmed = await _confirmTrustGuardProceed(context, trust);
    if (confirmed != true) return;
    if (!context.mounted) return;
  }

  // Capture a stable parent context before closing the action sheet.
  final navigator = Navigator.of(context);
  final parentContext = navigator.context;
  navigator.pop();

  final subject = 'Application for ${job.title}';
  final body =
      'Hi,\n\n'
      "I'm reaching out about the ${job.title} role at ${job.company}. "
      'I believe my background is a strong fit and I would welcome the '
      'chance to contribute.\n\n'
      "I've attached my resume — I'd love to discuss how I can help the "
      'team.\n\n'
      'Best regards,';

  final result = await EmailReviewPage.show(
    parentContext,
    recipient: resolveRecipient(job.company),
    subject: subject,
    body: body,
    mode: EmailReviewMode.draft,
  );

  if (!(result?.draftCreated ?? false)) return;
  if (!parentContext.mounted) return;

  ScaffoldMessenger.of(parentContext).showSnackBar(
    const SnackBar(content: Text('Draft saved to your Gmail Drafts.')),
  );
}

class _TrustGuardPreflight extends StatelessWidget {
  const _TrustGuardPreflight({required this.result});

  final JobTrustGuardResult result;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = switch (result.riskLevel) {
      'high' => brand.danger,
      'medium' => brand.warning,
      'low' => brand.success,
      _ => brand.textSoft,
    };

    final icon = switch (result.riskLevel) {
      'high' => Icons.warning_amber_rounded,
      'medium' => Icons.verified_user_outlined,
      _ => Icons.shield_outlined,
    };

    final subtitle = result.signals.isEmpty
        ? 'No obvious red flags found. Still verify the official posting.'
        : result.safeNextStep;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: brand.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Trust Guard · ${result.riskLabel}',
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 12.8,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: brand.textMuted,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
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
    final brand = context.brand;
    final color = destructive ? brand.danger : brand.ink;
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
