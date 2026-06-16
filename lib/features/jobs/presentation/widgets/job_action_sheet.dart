import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/brand_theme.dart';
import '../../../../data/models/job.dart';
import '../../../email/presentation/email_review_page.dart';
import '../../../email/services/recipient_resolver.dart';
import '../../state/jobs_notifier.dart';

class JobActionSheet {
  const JobActionSheet._();

  static Future<void> show(
    BuildContext context,
    Job job, {
    VoidCallback? onHide,
    VoidCallback? onDismiss,
    VoidCallback? onDrafted,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _JobActionSheetBody(
        job: job,
        onHide: onHide,
        onDismiss: onDismiss,
        onDrafted: onDrafted,
      ),
    );
  }
}

class _JobActionSheetBody extends ConsumerWidget {
  const _JobActionSheetBody({
    required this.job,
    this.onHide,
    this.onDismiss,
    this.onDrafted,
  });

  final Job job;
  final VoidCallback? onHide;
  final VoidCallback? onDismiss;
  final VoidCallback? onDrafted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final state = ref.watch(jobsProvider);
    final notifier = ref.read(jobsProvider.notifier);
    final isSaved = state.isSaved(job.id);
    final isHidden = state.isHidden(job.id);
    final label = '${job.title} at ${job.company}';

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
            _ActionTile(
              icon: Icons.drafts_outlined,
              label: 'Draft application email',
              onTap: () =>
                  draftJobEmail(context, ref, job, onDrafted: onDrafted),
            ),
            _ActionTile(
              icon: isSaved
                  ? Icons.bookmark_rounded
                  : Icons.bookmark_border_rounded,
              label: isSaved ? 'Saved' : 'Save for later',
              onTap: () {
                notifier.saveForLater(job, label: label);
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
                  onHide?.call();
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
                onDismiss?.call();
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

/// Opens the email review sheet pre-filled with a starter draft for [job],
/// then saves it to the user's Gmail Drafts (nothing is sent). The recipient
/// is a best-effort guess the user confirms in the sheet.
///
/// Shared by [JobActionSheet] and the application-link modal's email row so the
/// "draft an application email" behaviour lives in exactly one place.
Future<void> draftJobEmail(
  BuildContext context,
  WidgetRef ref,
  Job job, {
  VoidCallback? onDrafted,
}) async {
  final jobsNotifier = ref.read(jobsProvider.notifier);

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

  // Prefer a real address learned from a previous confirmed outreach to this
  // company; low-confidence guesses stay labeled in the review sheet.
  final recipientResolution = await resolveRecipientAsync(
    job.company,
    website: job.employerWebsite,
    applyLink: job.applyLink,
  );
  if (!parentContext.mounted) return;

  final result = await EmailReviewPage.show(
    parentContext,
    recipient: recipientResolution.email,
    subject: subject,
    body: body,
    mode: EmailReviewMode.draft,
    contactDomain: recipientResolution.domain.isNotEmpty
        ? recipientResolution.domain
        : recipientDomain(job.company, website: job.employerWebsite),
    company: job.company,
    recipientResolution: recipientResolution,
  );

  // The review sheet lets the user flip between "Save as draft" and "Send now",
  // so either outcome counts as acting on this job. Move it to Applications and
  // word the confirmation to match what actually happened.
  final sent = result?.sent ?? false;
  final drafted = result?.draftCreated ?? false;
  if (!sent && !drafted) return;

  await jobsNotifier.markDraftedJob(job);
  onDrafted?.call();

  if (!parentContext.mounted) return;

  ScaffoldMessenger.of(parentContext).showSnackBar(
    SnackBar(
      content: Text(
        sent
            ? 'Email sent and moved to Applications.'
            : 'Draft saved and moved to Applications.',
      ),
    ),
  );
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
