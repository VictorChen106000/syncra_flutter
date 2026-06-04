import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/route_names.dart';
import '../../../../core/theme/brand_theme.dart';
import '../../../../core/utils/motion.dart';
import '../../../../data/models/job.dart';
import '../../models/agent_block.dart';
import '../../state/agent_chat_notifier.dart';
import '../../../resumes/presentation/resume_draft_preview_page.dart';
import '../../../resumes/presentation/tailored_changes_page.dart';
import '../../../resumes/state/resume_notifier.dart';
import '../../../email/presentation/email_review_page.dart';
import '../../../email/services/gmail_service.dart';
import '../../../jobs/presentation/widgets/job_action_sheet.dart';

class AgentBlockView extends StatelessWidget {
  const AgentBlockView({
    super.key,
    required this.block,
    this.animateText = false,
  });

  final AgentBlock block;

  /// When true, a [TextBlock] types itself in character-by-character. Set by
  /// [AgentTurnView] only for the final block of a still-streaming turn.
  final bool animateText;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      ThinkingBlock(:final content) => ThinkingBlockView(content: content),
      ToolCallBlock() => ToolCallBlockView(block: block as ToolCallBlock),
      TextBlock(:final text) => _TextBlockView(
        text: text,
        animate: animateText,
      ),
      ProposedEditsBlock() => _ProposedEditsBlockView(
        block: block as ProposedEditsBlock,
      ),
      ResumeDraftBlock() => _ResumeDraftBlockView(
        block: block as ResumeDraftBlock,
      ),
      InputRequestBlock() => InputRequestView(
        block: block as InputRequestBlock,
      ),
      ActionProposalBlock() => ActionProposalView(
        block: block as ActionProposalBlock,
      ),
      EmailDraftBlock() => EmailDraftBlockView(block: block as EmailDraftBlock),
      JobsBlock() => JobsBlockView(block: block as JobsBlock),
    };
  }
}

/// A horizontally-swipeable rail of job matches the agent surfaced — the chat's
/// "generative UI" answer to a [JobsBlock]. Each role is a compact card in the
/// same visual language as the dashboard prompt cards (surface, radius-24, ink
/// icon chip). Tapping a card flips it to a "why this fits" face (the agent's
/// reasoning); a "See options" pill there opens the shared [JobActionSheet]
/// (save, draft an application email, share, dismiss) — all without leaving the
/// conversation.
class JobsBlockView extends StatelessWidget {
  const JobsBlockView({super.key, required this.block});

  final JobsBlock block;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final jobs = block.jobs;
    if (jobs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(
            '${jobs.length} ${jobs.length == 1 ? 'ROLE' : 'ROLES'} FOUND · SWIPE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
              color: brand.textMuted,
            ),
          ),
        ),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            clipBehavior: Clip.none,
            itemCount: jobs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              return _JobMatchCard(job: jobs[i])
                  .animate(delay: (i * 70).ms)
                  .fadeIn(duration: 300.ms)
                  .moveX(begin: 18, end: 0, curve: Curves.easeOutCubic);
            },
          ),
        ),
        const SizedBox(height: 12),
        const _SeeAllJobsButton(),
      ],
    );
  }
}

/// Footer CTA under the job rail — jumps to the full Jobs page where every
/// surfaced role (and the saved pipeline) lives.
class _SeeAllJobsButton extends StatelessWidget {
  const _SeeAllJobsButton();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => context.go(RouteNames.jobs),
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: brand.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See all in Jobs',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: brand.ink,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(width: 5),
              Icon(Icons.arrow_forward_rounded, size: 14, color: brand.ink),
            ],
          ),
        ),
      ),
    );
  }
}

/// One job in the [JobsBlockView] rail — a near-clone of the dashboard's prompt
/// suggestion card, adapted to carry a match-quality kicker, the role title,
/// and a company · salary subtitle.
/// Tapping the card flips it between its front (title + match) and a "why this
/// fits" face carrying the agent's one-line justification and any missing
/// skills — the chat's answer to "why did you surface this for me?". A small
/// "See options" pill on the back opens the shared [JobActionSheet] (save,
/// draft, share, dismiss). The flip stays inside the same card box so the
/// horizontal rail's height never shifts.
class _JobMatchCard extends StatefulWidget {
  const _JobMatchCard({required this.job});

  final Job job;

  @override
  State<_JobMatchCard> createState() => _JobMatchCardState();
}

class _JobMatchCardState extends State<_JobMatchCard> {
  bool _why = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final job = widget.job;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _why = !_why),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 232,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: brand.border),
            boxShadow: [
              BoxShadow(
                color: brand.shadow,
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _why ? _buildWhy(brand, job) : _buildFront(brand, job),
          ),
        ),
      ),
    );
  }

  Widget _buildFront(BrandTheme brand, Job job) {
    final (matchColor, matchLabel) = switch (job.category) {
      JobCategory.ready => (brand.success, 'ALL MATCH'),
      JobCategory.inputNeeded => (brand.textMuted, 'SEVERAL MATCH'),
      JobCategory.exploration => (brand.textSoft, 'NO MATCH'),
    };
    final subtitle = [
      if (job.company.isNotEmpty) job.company,
      if (job.salary.isNotEmpty) job.salary,
    ].join(' · ');

    return Column(
      key: const ValueKey('front'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: brand.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.work_outline_rounded,
                color: brand.onAccent,
                size: 18,
              ),
            ),
            const Spacer(),
            // A lightbulb hints there's reasoning behind this card — tap to see.
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: brand.surfaceMuted,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.lightbulb_outline_rounded,
                size: 14,
                color: brand.ink,
              ),
            ),
          ],
        ),
        const Spacer(),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: matchColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              matchLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
                color: brand.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          job.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: brand.ink,
            letterSpacing: -0.2,
            height: 1.25,
          ),
        ),
        if (subtitle.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: brand.textMuted,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildWhy(BrandTheme brand, Job job) {
    final justification = job.agentJustification.trim().isNotEmpty
        ? job.agentJustification.trim()
        : 'Syncra needs a quick review to confirm the strongest overlap.';
    final matched = job.skills.take(3).join(', ');
    final gaps = job.missingSkills.take(3).join(', ');

    return Column(
      key: const ValueKey('why'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, size: 15, color: brand.ink),
            const SizedBox(width: 6),
            Text(
              'WHY THIS FITS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: brand.textMuted,
              ),
            ),
            const Spacer(),
            Icon(Icons.close_rounded, size: 15, color: brand.textSoft),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          justification,
          maxLines: matched.isEmpty && gaps.isEmpty ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            fontWeight: FontWeight.w500,
            color: brand.ink,
          ),
        ),
        if (matched.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Matched: $matched',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: brand.textMuted,
            ),
          ),
        ],
        if (gaps.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Gap: $gaps',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: brand.textMuted,
            ),
          ),
        ],
        const Spacer(),
        Material(
          color: brand.surfaceMuted,
          borderRadius: BorderRadius.circular(99),
          child: InkWell(
            onTap: () => JobActionSheet.show(context, job),
            borderRadius: BorderRadius.circular(99),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'See options',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: brand.ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Icon(Icons.arrow_forward_rounded, size: 13, color: brand.ink),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Inline card for an [EmailDraftBlock]. Shows the drafted recipient/subject/
/// body and a single action that opens the review sheet in **draft mode** —
/// the user edits and saves it to their Gmail Drafts there. Nothing is ever
/// sent from the chat; the user finishes the send from Gmail.
class EmailDraftBlockView extends ConsumerWidget {
  const EmailDraftBlockView({super.key, required this.block});

  final EmailDraftBlock block;

  Future<void> _review(BuildContext context, WidgetRef ref) async {
    // Pull the tailored resume PDF down before opening the sheet so it rides
    // along as a real attachment on the Gmail draft. A missing blob is not
    // fatal — the draft still saves, just without the file.
    final attachments = await _loadAttachments(ref);
    if (!context.mounted) return;

    final result = await EmailReviewPage.show(
      context,
      recipient: block.recipient,
      subject: block.subject,
      body: block.body,
      mode: EmailReviewMode.draft,
      attachments: attachments,
    );
    if (result?.draftCreated ?? false) {
      ref
          .read(agentChatProvider.notifier)
          .markEmailDraftSaved(block.id, result!.draftId);
    }
  }

  /// Resolves the attachment list for this draft. Returns the tailored resume
  /// PDF bytes when [EmailDraftBlock.attachmentResumeId] is set and the blob
  /// downloads; otherwise an empty list.
  Future<List<EmailAttachment>> _loadAttachments(WidgetRef ref) async {
    final resumeId = block.attachmentResumeId;
    if (resumeId == null) return const [];

    final notifier = ref.read(resumeProvider.notifier);

    // Prefer freshly-primed bytes (the just-tailored PDF) so we don't depend on
    // the resumes stream having delivered the new doc yet. Fall back to a
    // download via the resume's storage path.
    var bytes = notifier.cachedBytesFor(resumeId);
    if (bytes == null) {
      final resume = ref
          .read(resumeProvider)
          .allResumes
          .where((r) => r.id == resumeId)
          .firstOrNull;
      if (resume == null) return const [];
      bytes = await notifier.bytesFor(resume);
    }
    if (bytes == null) return const [];

    return [
      EmailAttachment(
        filename: block.attachmentFilename ?? 'tailored_resume.pdf',
        bytes: bytes,
      ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final saved = block.status == EmailDraftStatus.saved;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: brand.border),
        boxShadow: [
          BoxShadow(
            color: brand.shadow.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: brand.accent,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.drafts_rounded,
                  color: brand.onAccent,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Draft recruiter outreach',
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (saved)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: brand.accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    'Saved',
                    style: TextStyle(
                      color: brand.onAccent,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _EmailMetaRow(label: 'TO', value: block.recipient),
          const SizedBox(height: 8),
          _EmailMetaRow(label: 'SUBJECT', value: block.subject),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: brand.surfaceMuted,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              block.body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: brand.textMuted,
                fontSize: 12.5,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (saved)
            Row(
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 15,
                  color: brand.success,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Saved to Gmail Drafts — review and send it from Gmail.',
                    style: TextStyle(
                      color: brand.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            )
          else
            _FooterButton(
              label: 'Review & save draft',
              filled: true,
              enabled: true,
              onTap: () => _review(context, ref),
            ),
        ],
      ),
    );
  }
}

/// One label/value line ("TO recipient@…") inside [EmailDraftBlockView].
class _EmailMetaRow extends StatelessWidget {
  const _EmailMetaRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: Text(
            label,
            style: TextStyle(
              color: brand.textSoft,
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.0,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: brand.ink,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }
}

/// Inline card for a [ResumeDraftBlock] — a resume the agent built from
/// scratch. While [ResumeDraftState.rendering] it shows a spinner; once the
/// notifier renders the PDF the card offers a magnifying glass that opens the
/// full-screen preview where the user saves it to their library.
class _ResumeDraftBlockView extends ConsumerWidget {
  const _ResumeDraftBlockView({required this.block});

  final ResumeDraftBlock block;

  String get _summaryLine {
    final parts = <String>[];
    final exp = block.resume.experience.length;
    final edu = block.resume.education.length;
    final skills = block.resume.skills.length;
    if (exp > 0) parts.add('$exp ${exp == 1 ? 'role' : 'roles'}');
    if (edu > 0) parts.add('$edu ${edu == 1 ? 'school' : 'schools'}');
    if (skills > 0) parts.add('$skills ${skills == 1 ? 'skill' : 'skills'}');
    final name = block.resume.header.name.trim();
    final detail = parts.join(' · ');
    if (name.isEmpty) return detail;
    return detail.isEmpty ? name : '$name · $detail';
  }

  void _openPreview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ResumeDraftPreviewPage(blockId: block.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final saved = block.isSaved;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: brand.border),
        boxShadow: [
          BoxShadow(
            color: brand.shadow.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: brand.accent,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.note_add_rounded,
                  color: brand.onAccent,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'New resume',
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
          if (_summaryLine.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _summaryLine,
              style: TextStyle(
                color: brand.textMuted,
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          _footer(context, brand, saved),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, BrandTheme brand, bool saved) {
    if (block.state == ResumeDraftState.rendering) {
      return Row(
        children: [
          const SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 9),
          Text(
            'Rendering your resume…',
            style: TextStyle(
              color: brand.textMuted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ],
      );
    }

    // Ready: rendered (or render failed). Surface the error if there are no
    // bytes to preview; otherwise the magnifying glass opens the preview.
    if (block.previewBytes == null) {
      return _ErrorLine(
        message: block.error ?? 'Could not render this resume.',
      );
    }

    return Row(
      children: [
        Icon(
          saved ? Icons.check_circle_rounded : Icons.auto_awesome_rounded,
          size: 15,
          color: saved ? brand.success : brand.ink,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            saved ? 'Saved to your resumes' : 'Draft ready — tap to review',
            style: TextStyle(
              color: brand.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(width: 8),
        _PreviewIconButton(onTap: () => _openPreview(context)),
      ],
    );
  }
}

class _ProposedEditsBlockView extends StatelessWidget {
  const _ProposedEditsBlockView({required this.block});

  final ProposedEditsBlock block;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final count = block.edits.length;
    final plural = count == 1 ? 'edit' : 'edits';
    final headline = switch (block.state) {
      ProposedEditsState.applying => 'Tuning your resume…',
      ProposedEditsState.applied => 'Resume tuned for this role',
      ProposedEditsState.dismissed => 'Changes dismissed',
      ProposedEditsState.reviewing => '$count suggested $plural',
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: brand.border),
        boxShadow: [
          BoxShadow(
            color: brand.shadow.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: brand.accent,
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.difference_rounded,
                  color: brand.onAccent,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  headline,
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              _StatusPill(block: block),
            ],
          ),
          const SizedBox(height: 12),
          _EditsFooter(block: block),
        ],
      ),
    );
  }
}

/// The card's action row. While reviewing it offers "Apply N edits" (enabled
/// only once at least one edit is accepted) and "Dismiss all"; once settled it
/// collapses to a one-line outcome.
class _EditsFooter extends ConsumerWidget {
  const _EditsFooter({required this.block});

  final ProposedEditsBlock block;

  void _openPreview(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => TailoredChangesPage(blockId: block.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final notifier = ref.read(agentChatProvider.notifier);

    switch (block.state) {
      case ProposedEditsState.dismissed:
        return _SettledLine(
          icon: Icons.history_rounded,
          color: brand.textMuted,
          text: 'Dismissed — no changes were made',
        );

      case ProposedEditsState.applying:
        return Row(
          children: [
            const SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 9),
            Text(
              'Rendering your tailored resume…',
              style: TextStyle(
                color: brand.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.1,
              ),
            ),
          ],
        );

      case ProposedEditsState.applied:
        // Preview is ready (and maybe saved). The applied edits live in the
        // resume already — the button opens the full-screen live resume where
        // the changed lines glow and the user saves or keeps editing.
        final saved = block.isSaved;
        final applied = block.appliedCount;
        final skipped = block.skippedCount > 0
            ? ' · ${block.skippedCount} skipped'
            : '';
        final status = saved
            ? 'Saved to your resumes'
            : applied > 0
            ? '$applied improvement${applied == 1 ? '' : 's'}'
                  ' woven in$skipped'
            : 'Already a strong fit — no changes needed';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  saved
                      ? Icons.check_circle_rounded
                      : Icons.auto_awesome_rounded,
                  size: 15,
                  color: saved ? brand.success : brand.ink,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    status,
                    style: TextStyle(
                      color: brand.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _FooterButton(
                label: saved ? 'View resume' : 'See what changed',
                filled: !saved,
                enabled: true,
                onTap: () => _openPreview(context),
              ),
            ),
          ],
        );

      case ProposedEditsState.reviewing:
        final count = block.acceptedCount;
        final canApply = count > 0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (block.applyError != null) ...[
              _ErrorLine(message: block.applyError!),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                _FooterButton(
                  label: 'Dismiss all',
                  filled: false,
                  enabled: true,
                  onTap: () => notifier.dismissProposedEdits(block.id),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _FooterButton(
                    label: canApply
                        ? 'Apply $count ${count == 1 ? 'edit' : 'edits'}'
                        : 'Apply edits',
                    filled: true,
                    enabled: canApply,
                    onTap: () => notifier.applyProposedEdits(block.id),
                  ),
                ),
              ],
            ),
          ],
        );
    }
  }
}

/// One-line settled footer (dismissed state).
class _SettledLine extends StatelessWidget {
  const _SettledLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline_rounded, size: 15, color: brand.danger),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: brand.danger,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}

/// The magnifying-glass affordance that opens the tailored-PDF preview.
class _PreviewIconButton extends StatelessWidget {
  const _PreviewIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.accent,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          child: Icon(Icons.zoom_in_rounded, size: 19, color: brand.onAccent),
        ),
      ),
    );
  }
}

class _FooterButton extends StatelessWidget {
  const _FooterButton({
    required this.label,
    required this.filled,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bg = filled ? brand.accent : Colors.transparent;
    final fg = filled ? brand.onAccent : brand.ink;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: filled ? brand.accent : brand.border),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: -0.1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Header chip summarising where the card stands: a live accepted count while
/// reviewing, or a settled label once applied/dismissed.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.block});

  final ProposedEditsBlock block;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final (label, fg, bg) = switch (block.state) {
      ProposedEditsState.applied =>
        block.isSaved
            ? ('Saved', brand.onAccent, brand.accent)
            : ('Preview ready', brand.onAccent, brand.accent),
      ProposedEditsState.applying => (
        'Rendering…',
        brand.textMuted,
        brand.surfaceMuted,
      ),
      ProposedEditsState.dismissed => (
        'Dismissed',
        brand.textMuted,
        brand.surfaceMuted,
      ),
      ProposedEditsState.reviewing => (
        '${block.acceptedCount}/${block.edits.length} accepted',
        brand.textMuted,
        brand.surfaceMuted,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class InputRequestView extends ConsumerStatefulWidget {
  const InputRequestView({super.key, required this.block});

  final InputRequestBlock block;

  @override
  ConsumerState<InputRequestView> createState() => _InputRequestViewState();
}

class _InputRequestViewState extends ConsumerState<InputRequestView> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.block.answer ?? '',
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    ref
        .read(agentChatProvider.notifier)
        .submitInputAnswer(widget.block.id, trimmed);
    _focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final answered = widget.block.state == InputRequestState.answered;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: answered ? brand.surfaceMuted : brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: answered ? brand.border : brand.accent,
          width: answered ? 1 : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                answered
                    ? Icons.check_circle_rounded
                    : Icons.question_answer_rounded,
                size: 16,
                color: answered ? brand.textMuted : brand.ink,
              ),
              const SizedBox(width: 8),
              Text(
                'AGENT NEEDS YOUR INPUT',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: brand.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            widget.block.question,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: brand.ink,
              height: 1.4,
              letterSpacing: -0.1,
            ),
          ),
          const SizedBox(height: 12),
          if (answered)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: brand.border),
              ),
              child: Text(
                widget.block.answer ?? '',
                style: TextStyle(
                  fontSize: 13.5,
                  color: brand.ink,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            )
          else ...[
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: _submit,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: brand.ink,
              ),
              decoration: InputDecoration(
                hintText: 'Type your answer…',
                hintStyle: TextStyle(
                  color: brand.textSoft,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                filled: true,
                fillColor: brand.surfaceMuted,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                  color: brand.ink,
                  onPressed: () => _submit(_controller.text),
                ),
              ),
            ),
            if (widget.block.suggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in widget.block.suggestions)
                    _SuggestionChip(
                      label: s,
                      onTap: () {
                        _controller.text = s;
                        _submit(s);
                      },
                    ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: brand.surface,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(99),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: brand.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: brand.ink,
            ),
          ),
        ),
      ),
    );
  }
}

/// Agent prose. While [animate] is set (the final block of a streaming turn)
/// the text reveals itself character-by-character with a trailing caret. Once
/// fully revealed — or for any already-finished turn — it renders instantly,
/// so scrolling back through history never replays the typewriter.
class _TextBlockView extends StatefulWidget {
  const _TextBlockView({required this.text, this.animate = false});

  final String text;
  final bool animate;

  @override
  State<_TextBlockView> createState() => _TextBlockViewState();
}

class _TextBlockViewState extends State<_TextBlockView> {
  int _shown = 0;
  Timer? _timer;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.animate && widget.text.isNotEmpty && shouldAnimate(context)) {
      _startTyping();
    } else {
      _shown = widget.text.length;
    }
  }

  void _startTyping() {
    final len = widget.text.length;
    // Reveal in ~1.3s regardless of length so short and long replies both
    // feel snappy rather than scaling linearly with character count.
    final step = (len / 80).ceil().clamp(1, len);
    _timer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _shown = (_shown + step).clamp(0, len));
      if (_shown >= len) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final typing = _shown < widget.text.length;
    // Trailing block caret while typing — reads as a live cursor.
    final data = typing ? '${widget.text.substring(0, _shown)}▌' : widget.text;
    // Agent prose renders in a serif (Source Serif 4) to set the AI's
    // "voice" apart from the all-Inter UI chrome — the same chrome/serif
    // split Claude's mobile app uses.
    final body = GoogleFonts.sourceSerif4(
      color: brand.ink,
      fontSize: 16,
      height: 1.62,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    );
    return MarkdownBody(
      data: data,
      // Selection mid-type fights the reveal; enable it once settled.
      selectable: !typing,
      shrinkWrap: true,
      onTapLink: (text, href, title) {
        // Links are non-actionable for now; surfacing them via launchUrl can
        // be wired through the router later. Swallowing keeps the chat from
        // throwing on stray markdown URLs in agent output.
      },
      styleSheet: MarkdownStyleSheet(
        p: body,
        strong: body.copyWith(fontWeight: FontWeight.w800),
        em: body.copyWith(fontStyle: FontStyle.italic),
        a: body.copyWith(
          color: brand.accent,
          decoration: TextDecoration.underline,
        ),
        h1: body.copyWith(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          height: 1.3,
          letterSpacing: -0.3,
        ),
        h2: body.copyWith(
          fontSize: 17.5,
          fontWeight: FontWeight.w800,
          height: 1.3,
          letterSpacing: -0.2,
        ),
        h3: body.copyWith(
          fontSize: 15.5,
          fontWeight: FontWeight.w800,
          height: 1.35,
          letterSpacing: -0.15,
        ),
        listBullet: body,
        code: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Courier'],
          fontSize: 13.5,
          color: brand.ink,
          backgroundColor: brand.surfaceMuted,
          height: 1.4,
        ),
        codeblockDecoration: BoxDecoration(
          color: brand.surfaceMuted,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: brand.border, width: 0.6),
        ),
        codeblockPadding: const EdgeInsets.all(12),
        blockquote: body.copyWith(
          color: brand.textMuted,
          fontStyle: FontStyle.italic,
        ),
        blockquoteDecoration: BoxDecoration(
          color: brand.surfaceMuted,
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: brand.border, width: 3)),
        ),
        blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        blockSpacing: 10,
        h1Padding: const EdgeInsets.only(top: 6, bottom: 2),
        h2Padding: const EdgeInsets.only(top: 6, bottom: 2),
        h3Padding: const EdgeInsets.only(top: 4, bottom: 2),
      ),
    );
  }
}

class ThinkingBlockView extends StatefulWidget {
  const ThinkingBlockView({super.key, required this.content});
  final String content;

  @override
  State<ThinkingBlockView> createState() => _ThinkingBlockViewState();
}

class _ThinkingBlockViewState extends State<ThinkingBlockView> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ShimmerText(
                    text: 'Thought for a moment',
                    active: !_expanded,
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: _expanded ? 0.5 : 0,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 16,
                      color: brand.textSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: _expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity, height: 0),
          secondChild: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: brand.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.content,
                      style: TextStyle(
                        color: brand.textMuted,
                        fontSize: 13.5,
                        height: 1.6,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        letterSpacing: -0.05,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShimmerText extends StatelessWidget {
  const _ShimmerText({required this.text, required this.active});
  final String text;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final base = Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: brand.textMuted,
        letterSpacing: -0.1,
      ),
    );
    if (!active) return base;
    return base
        .animate(onPlay: repeatIfMotion(context))
        .shimmer(duration: 1600.ms, color: brand.ink.withValues(alpha: 0.55));
  }
}

class ToolCallBlockView extends StatelessWidget {
  const ToolCallBlockView({super.key, required this.block});

  final ToolCallBlock block;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final running = block.status == ToolCallStatus.running;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: running
                    ? const _Spinner()
                    : Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: brand.textMuted,
                      ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: running
                    ? _ShimmerText(text: block.label, active: true)
                    : Text(
                        block.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: brand.textMuted,
                          letterSpacing: -0.1,
                        ),
                      ),
              ),
            ],
          ),
          if (!running && block.resultSummary != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 26),
              child: Text(
                block.resultSummary!,
                style: TextStyle(
                  color: brand.textSoft,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Icon(
          Icons.refresh_rounded,
          size: 14,
          color: brand.textMuted.withValues(alpha: 0.85),
        )
        .animate(onPlay: repeatIfMotion(context))
        .rotate(duration: 900.ms, curve: Curves.linear);
  }
}

class ActionProposalView extends StatelessWidget {
  const ActionProposalView({super.key, required this.block});

  final ActionProposalBlock block;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final accepted = block.state == ActionState.accepted;
    final dismissed = block.state == ActionState.dismissed;
    final settled = accepted || dismissed;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accepted ? brand.ink : brand.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accepted ? brand.ink : brand.border),
        boxShadow: accepted
            ? [
                BoxShadow(
                  color: brand.ink.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accepted ? brand.accent : brand.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  block.icon,
                  size: 18,
                  color: accepted ? brand.onAccent : brand.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      block.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: accepted ? brand.inkInverse : brand.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      block.description,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: accepted
                            ? brand.inkInverse.withValues(alpha: 0.78)
                            : brand.textMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (settled)
            _SettledFooter(accepted: accepted)
          else
            _ActionRow(block: block),
        ],
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.block});

  final ActionProposalBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: _ProposalButton(
            label: block.editLabel,
            icon: Icons.tune_rounded,
            filled: false,
            onTap: () =>
                ref.read(agentChatProvider.notifier).dismissProposal(block.id),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ProposalButton(
            label: block.acceptLabel,
            icon: Icons.check_rounded,
            filled: true,
            onTap: () =>
                ref.read(agentChatProvider.notifier).acceptProposal(block.id),
          ),
        ),
      ],
    );
  }
}

class _SettledFooter extends StatelessWidget {
  const _SettledFooter({required this.accepted});
  final bool accepted;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      children: [
        Icon(
          accepted ? Icons.check_circle_rounded : Icons.history_rounded,
          size: 14,
          color: accepted ? brand.accent : brand.textMuted,
        ),
        const SizedBox(width: 6),
        Text(
          accepted
              ? 'Accepted · running now'
              : 'Reverted — tell me how to adjust',
          style: TextStyle(
            color: accepted
                ? brand.inkInverse.withValues(alpha: 0.88)
                : brand.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

class _ProposalButton extends StatelessWidget {
  const _ProposalButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bg = filled ? brand.accent : Colors.transparent;
    final fg = filled ? brand.onAccent : brand.ink;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: filled ? brand.accent : brand.border),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: fg, size: 14),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
