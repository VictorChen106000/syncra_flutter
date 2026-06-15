import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
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
import '../../../resumes/models/resume_integrity_result.dart';
import '../../../resumes/presentation/resume_draft_preview_page.dart';
import '../../../resumes/presentation/tailored_changes_page.dart';
import '../../../resumes/state/resume_notifier.dart';
import '../../../email/presentation/email_review_page.dart';
import '../../../email/services/gmail_service.dart';
import '../../../jobs/presentation/widgets/job_action_sheet.dart';
import '../../../jobs/services/job_trust_guard.dart';
import '../../../jobs/state/jobs_notifier.dart';
import '../../../../data/firestore/jobs_repository.dart';
import '../../../auth/models/user_profile.dart';
import '../../../auth/state/user_profile_notifier.dart';
import '../../../email/services/email_send_service.dart';

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
/// icon chip) showing the match tier, title, company · salary, and the agent's
/// one-line reasoning. Tapping a card opens the shared [JobActionSheet] (save,
/// draft an application email, share, dismiss) without leaving the conversation.
class JobsBlockView extends ConsumerWidget {
  const JobsBlockView({super.key, required this.block});

  final JobsBlock block;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final jobsState = ref.watch(jobsProvider);

    final dismissedIds = <String>{
      ...block.dismissedJobIds,
      ...jobsState.dismissedIds,
    };
    final hiddenIds = <String>{...block.hiddenJobIds, ...jobsState.hiddenIds}
      ..removeAll(dismissedIds);
    final handledIds = <String>{...block.handledJobIds};

    final inactiveIds = <String>{...dismissedIds, ...hiddenIds, ...handledIds};

    final jobs = block.jobs
        .where((job) => !inactiveIds.contains(job.id))
        .toList(growable: false);

    final totalCount = block.jobs.length;
    final dismissedCount = block.jobs
        .where((job) => dismissedIds.contains(job.id))
        .length;
    final hiddenCount = block.jobs
        .where((job) => hiddenIds.contains(job.id))
        .length;
    final handledCount = block.jobs
        .where((job) => handledIds.contains(job.id))
        .length;

    if (jobs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No visible roles left in this result set.',
          style: TextStyle(
            color: brand.textMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: Text(
            _jobsHeader(
              visibleCount: jobs.length,
              totalCount: totalCount,
              dismissedCount: dismissedCount,
              hiddenCount: hiddenCount,
              handledCount: handledCount,
            ),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.4,
              color: brand.textMuted,
            ),
          ),
        ),
        if (hiddenCount > 0) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => ref
                  .read(agentChatProvider.notifier)
                  .unhideAllJobsInBlock(block.id),
              icon: const Icon(Icons.visibility_outlined, size: 15),
              label: Text(
                hiddenCount == 1
                    ? 'Show 1 hidden role'
                    : 'Show $hiddenCount hidden roles',
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            clipBehavior: Clip.none,
            itemCount: jobs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              return _JobMatchCard(
                    job: jobs[i],
                    onHide: () => ref
                        .read(agentChatProvider.notifier)
                        .hideJobInBlock(block.id, jobs[i].id),
                    onDismiss: () => ref
                        .read(agentChatProvider.notifier)
                        .dismissJobInBlock(block.id, jobs[i].id),
                    onDrafted: () => ref
                        .read(agentChatProvider.notifier)
                        .markJobHandledInBlock(block.id, jobs[i].id),
                  )
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

String _jobsHeader({
  required int visibleCount,
  required int totalCount,
  required int dismissedCount,
  required int hiddenCount,
  required int handledCount,
}) {
  final roleLabel = visibleCount == 1 ? 'ROLE' : 'ROLES';
  final parts = <String>['$visibleCount OF $totalCount $roleLabel'];

  if (dismissedCount > 0) {
    parts.add('$dismissedCount DISMISSED');
  }
  if (hiddenCount > 0) {
    parts.add('$hiddenCount HIDDEN');
  }
  if (handledCount > 0) {
    parts.add('$handledCount HANDLED');
  }

  parts.add('SWIPE');
  return parts.join(' · ');
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

/// One job in the [JobsBlockView] rail — a compact card in the dashboard's
/// prompt-suggestion language (surface, radius-24, accent icon chip). It shows
/// the match tier, the role title, a company · salary subtitle, and a one-line
/// "why this fits" from the agent — everything visible at once, no hidden face.
/// A single tap opens the shared [JobActionSheet] (save, draft an application
/// email, share, hide, dismiss) without leaving the conversation.
class _JobMatchCard extends StatelessWidget {
  const _JobMatchCard({
    required this.job,
    required this.onHide,
    required this.onDismiss,
    required this.onDrafted,
  });

  final Job job;
  final VoidCallback onHide;
  final VoidCallback onDismiss;
  final VoidCallback onDrafted;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // The match label itself comes from the model ([Job.matchLabel]); only the
    // dot colour is presentational and lives here.
    final matchColor = switch (job.category) {
      JobCategory.ready => brand.success,
      JobCategory.inputNeeded => brand.textMuted,
      JobCategory.exploration => brand.textSoft,
    };
    final subtitle = [
      if (job.company.isNotEmpty) job.company,
      if (job.salary.isNotEmpty) job.salary,
    ].join(' · ');
    final why = job.agentJustification.trim().isNotEmpty
        ? job.agentJustification.trim()
        : job.why.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => JobActionSheet.show(
          context,
          job,
          onHide: onHide,
          onDismiss: onDismiss,
          onDrafted: onDrafted,
        ),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: brand.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: brand.border),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.work_outline_rounded,
                      color: brand.ink,
                      size: 18,
                    ),
                  ),
                  const Spacer(),
                  // The match dot + label only appear once the AI matcher has
                  // actually scored the role. Roles freshly surfaced by
                  // search_jobs are unmatched, so the rail stays silent on fit
                  // rather than showing a misleading "All Match".
                  if (job.matched) ...[
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
                      job.matchLabel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: brand.textMuted,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
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
              // The agent's one-line reasoning, pinned to the bottom of the
              // card. Expanded soaks up the slack so the row never overflows
              // the fixed rail height, and the text ellipsizes within it.
              if (why.isNotEmpty)
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              size: 13,
                              color: brand.accent,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              why,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.35,
                                fontWeight: FontWeight.w500,
                                color: brand.textMuted,
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
          ),
        ),
      ),
    );
  }
}

/// Inline card for an [EmailDraftBlock]. Shows the drafted recipient/subject/
/// body and a single action that opens the review sheet in **send mode** — the
/// user edits the recipient/subject/body and taps Send, which mints the one-shot
/// confirmation token and delivers via Gmail. The agent still never sends on its
/// own; the send only happens on the user's explicit tap inside the sheet.
class EmailDraftBlockView extends ConsumerStatefulWidget {
  const EmailDraftBlockView({super.key, required this.block});

  final EmailDraftBlock block;

  @override
  ConsumerState<EmailDraftBlockView> createState() =>
      _EmailDraftBlockViewState();
}

class _EmailDraftBlockViewState extends ConsumerState<EmailDraftBlockView> {
  /// Length of the Autopilot "Undo" window before the email actually sends.
  static const _undoWindow = Duration(seconds: 5);

  /// True while an auto-send is in flight — drives the "Auto-sending…" footer.
  bool _autoSending = false;

  /// Guards the one-shot auto-send so rebuilds / post-frame callbacks can't
  /// fire it twice. Set on the first attempt whether or not it ends up sending.
  bool _autoSendStarted = false;

  /// True once this card actually auto-sent, so the settled state can say so.
  bool _autoSent = false;

  /// Counts down the Autopilot undo window; non-null only while it's open.
  Timer? _undoTimer;

  /// Seconds left in the undo window — drives the "Sending in Ns… Undo" footer.
  /// Zero means no window is open.
  int _undoRemaining = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoSend());
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }

  /// In **Autopilot** ([AutonomyLevel.autopilot]) the agent's outreach is sent
  /// for the user — but only when the job clears the low-risk trust floor and
  /// the recipient is a real address, and always behind a brief [_undoWindow]
  /// so the user can catch it. Any miss — wrong mode, missing/risky job, bad
  /// recipient — falls back to the manual "Review & send" card. Never fires for
  /// restored history: only blocks built live this session carry
  /// [EmailDraftBlock.autoSendPending].
  Future<void> _maybeAutoSend() async {
    if (_autoSendStarted) return;
    final block = widget.block;
    if (!block.autoSendPending || block.status != EmailDraftStatus.reviewing) {
      return;
    }
    final level =
        ref.read(userProfileProvider)?.autonomyLevel ?? AutonomyLevel.autopilot;
    if (level != AutonomyLevel.autopilot) return;
    if (!_looksLikeEmail(block.recipient)) return; // Guessed/blank → review.
    final jobId = block.jobId;
    if (jobId == null || jobId.isEmpty) return;

    _autoSendStarted = true;
    try {
      final job = await JobsRepository().fetchById(jobId);
      if (job == null) return; // Can't assess risk → manual review.
      if (evaluateJobTrust(job).riskLevel != 'low') {
        return; // Medium/high risk → manual review.
      }
      if (!mounted) return;
      // Open the undo window. The actual send fires when it elapses.
      setState(() => _undoRemaining = _undoWindow.inSeconds);
      _undoTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_undoRemaining <= 1) {
          timer.cancel();
          _undoTimer = null;
          _performAutoSend(job.company);
        } else {
          setState(() => _undoRemaining -= 1);
        }
      });
    } catch (e) {
      debugPrint('EmailDraftBlockView: auto-send setup failed ($e)');
    }
  }

  /// User caught the Autopilot send during the undo window: cancel it and drop
  /// back to the manual "Review & send" card.
  void _cancelAutoSend() {
    _undoTimer?.cancel();
    _undoTimer = null;
    if (mounted) setState(() => _undoRemaining = 0);
  }

  /// Performs the confirmed Autopilot send once the undo window elapses.
  Future<void> _performAutoSend(String company) async {
    if (!mounted) return;
    final block = widget.block;
    setState(() {
      _undoRemaining = 0;
      _autoSending = true;
    });
    try {
      final attachments = await _loadAttachments();
      final result = await EmailSendService.instance.autoSend(
        to: block.recipient,
        subject: block.subject,
        body: block.body,
        uid: FirebaseAuth.instance.currentUser?.uid,
        attachments: attachments,
        company: company,
      );
      if (!mounted) return;
      _autoSent = true;
      ref
          .read(agentChatProvider.notifier)
          .markEmailDraftSent(block.id, result.messageId);
    } catch (e) {
      // Best-effort: drop back to the manual card so the user can still send.
      debugPrint('EmailDraftBlockView: auto-send failed, manual fallback ($e)');
    } finally {
      if (mounted && _autoSending) setState(() => _autoSending = false);
    }
  }

  /// Light sanity check that a recipient is a real address, not a placeholder
  /// the agent couldn't resolve — Autopilot won't auto-send to a guess.
  static bool _looksLikeEmail(String value) {
    final v = value.trim();
    return v.contains('@') && v.contains('.') && !v.contains(' ');
  }

  Future<void> _review(BuildContext context) async {
    final block = widget.block;
    // Pull the tailored resume PDF down before opening the sheet so it rides
    // along as a real attachment on the Gmail draft. A missing blob is not
    // fatal — the draft still saves, just without the file.
    final attachments = await _loadAttachments();
    if (!context.mounted) return;

    final result = await EmailReviewPage.show(
      context,
      recipient: block.recipient,
      subject: block.subject,
      body: block.body,
      mode: EmailReviewMode.send,
      attachments: attachments,
    );
    if (!context.mounted) return;
    final notifier = ref.read(agentChatProvider.notifier);
    if (result?.sent ?? false) {
      notifier.markEmailDraftSent(block.id, result!.messageId);
    } else if (result?.draftCreated ?? false) {
      notifier.markEmailDraftSaved(block.id, result!.draftId);
    }
  }

  /// Resolves the attachment list for this draft. Returns the tailored resume
  /// PDF bytes when [EmailDraftBlock.attachmentResumeId] is set and the blob
  /// downloads; otherwise an empty list.
  Future<List<EmailAttachment>> _loadAttachments() async {
    final block = widget.block;
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
  Widget build(BuildContext context) {
    final block = widget.block;
    final brand = context.brand;
    final sent = block.status == EmailDraftStatus.sent;
    final saved = block.status == EmailDraftStatus.saved;
    final settled = sent || saved;

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
                  color: brand.surfaceMuted,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: brand.border),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.drafts_rounded,
                  color: brand.ink,
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
              if (settled)
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
                    sent ? 'Sent' : 'Saved',
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
          if (settled)
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
                    saved
                        ? 'Saved to Gmail Drafts — review and send it from Gmail.'
                        : _autoSent
                        ? 'Auto-sent to ${block.recipient} on Autopilot.'
                        : 'Email sent to ${block.recipient}.',
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
          else if (_undoRemaining > 0)
            Row(
              children: [
                Icon(Icons.bolt_rounded, size: 15, color: brand.accent),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Autopilot — sending in ${_undoRemaining}s…',
                    style: TextStyle(
                      color: brand.ink,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _cancelAutoSend,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Undo',
                    style: TextStyle(
                      color: brand.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            )
          else if (_autoSending)
            Row(
              children: [
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(brand.accent),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Auto-sending…',
                  style: TextStyle(
                    color: brand.textMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            )
          else
            _FooterButton(
              label: 'Review & send',
              filled: true,
              enabled: true,
              onTap: () => _review(context),
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
                  color: brand.surfaceMuted,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: brand.border),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.difference_rounded,
                  color: brand.ink,
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
        final repairing = block.integrityAutoRepairing;
        final applied = block.appliedCount;
        final skipped = block.skippedCount > 0
            ? ' · ${block.skippedCount} skipped'
            : '';
        final status = repairing
            ? 'Integrity check found issues'
            : saved
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
                  repairing
                      ? Icons.autorenew_rounded
                      : saved
                      ? Icons.check_circle_rounded
                      : Icons.auto_awesome_rounded,
                  size: 15,
                  color: repairing
                      ? brand.warning
                      : saved
                      ? brand.success
                      : brand.ink,
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
            if (block.integrity != null) ...[
              const SizedBox(height: 8),
              _IntegrityLine(block: block),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _FooterButton(
                // Inspection, not a commit — kept as a quiet outlined button so
                // the only filled accent on screen is the irreversible action
                // (e.g. the email card's Review & send).
                label: saved ? 'View resume' : 'See what changed',
                filled: false,
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

class _IntegrityLine extends StatelessWidget {
  const _IntegrityLine({required this.block});

  final ProposedEditsBlock block;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final result = block.integrity!;
    final repaired = block.integrityRepairAttempted;
    final (icon, color, text) = block.supersededByBlockId != null
        ? (
            Icons.auto_awesome_rounded,
            brand.success,
            'A safer revision is ready below.',
          )
        : block.integrityAutoRepairing
        ? (
            Icons.autorenew_rounded,
            brand.warning,
            'Integrity check found issues — Syncra is repairing this automatically.',
          )
        : switch (result.status) {
            ResumeIntegrityStatus.verified => (
              Icons.verified_rounded,
              brand.success,
              'Integrity verified — accepted edits landed and original facts were preserved.',
            ),
            ResumeIntegrityStatus.needsReview => (
              Icons.warning_amber_rounded,
              brand.warning,
              repaired
                  ? 'Needs review — Syncra tried one safer pass. Review before saving.'
                  : 'Needs review — Syncra found possible unsupported claims. Review before saving.',
            ),
            ResumeIntegrityStatus.blocked => (
              Icons.block_rounded,
              brand.danger,
              repaired
                  ? 'Blocked — Syncra could not safely repair this. Saving is disabled.'
                  : 'Blocked — Syncra found a serious integrity issue. Saving is disabled.',
            ),
          };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: brand.ink,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
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
    // Outlined buttons sit on a muted fill (not transparent) so they still read
    // as a tappable control next to the one filled-accent primary.
    final bg = filled ? brand.accent : brand.surfaceMuted;
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
    // Neutral pill on every state; a single colored dot carries the status so
    // the chip doesn't compete with the card's one filled-accent action.
    final (label, dot) = switch (block.state) {
      ProposedEditsState.applied =>
        block.integrityAutoRepairing
            ? ('Repairing…', brand.warning)
            : block.isSaved
            ? ('Saved', brand.success)
            : ('Preview ready', brand.accent),
      ProposedEditsState.applying => ('Rendering…', brand.textSoft),
      ProposedEditsState.dismissed => ('Dismissed', brand.textSoft),
      ProposedEditsState.reviewing => (
        '${block.acceptedCount}/${block.edits.length} accepted',
        brand.textSoft,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: brand.surfaceMuted,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: brand.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: brand.ink,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.1,
            ),
          ),
        ],
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

  /// The prose actually rendered. Any Markdown table the model emitted is
  /// flattened into bullets here so the chat never draws a grid — see
  /// [_flattenMarkdownTables]. The typing animation runs over this text.
  late final String _text = _flattenMarkdownTables(widget.text);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (widget.animate && _text.isNotEmpty && shouldAnimate(context)) {
      _startTyping();
    } else {
      _shown = _text.length;
    }
  }

  void _startTyping() {
    final len = _text.length;
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
    final typing = _shown < _text.length;
    // Trailing block caret while typing — reads as a live cursor.
    final data = typing ? '${_text.substring(0, _shown)}▌' : _text;
    // Agent prose uses the app's one typeface (Inter) so the chat reads as a
    // single, consistent surface — no serif/sans split.
    final body = GoogleFonts.inter(
      color: brand.ink,
      fontSize: 15.5,
      height: 1.58,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
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
        code: GoogleFonts.inter(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
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

/// Rewrites any GitHub-flavoured Markdown table into a bulleted list so the chat
/// never renders a grid. `flutter_markdown` draws real `<table>` columns, which
/// overflow and read terribly on a phone — the product rule is that job
/// comparisons live in the swipeable job rail, not a table. The system prompt
/// already tells the agent not to emit tables; this is the backstop for when it
/// does anyway. Each data row becomes one bullet whose first cell is bolded and
/// whose remaining non-empty cells follow as "Header: value" fragments joined by
/// " · ". Text with no table passes through untouched.
String _flattenMarkdownTables(String input) {
  if (!input.contains('|')) return input;

  final lines = input.split('\n');
  final out = <String>[];
  var i = 0;
  while (i < lines.length) {
    final header = lines[i];
    final separator = i + 1 < lines.length ? lines[i + 1] : '';
    if (_looksLikeTableRow(header) && _isTableSeparator(separator)) {
      final headers = _splitTableRow(header);
      i += 2; // Consume the header and the `--- | ---` separator row.
      while (i < lines.length && _looksLikeTableRow(lines[i])) {
        out.add(_tableRowToBullet(headers, _splitTableRow(lines[i])));
        i++;
      }
      continue;
    }
    out.add(header);
    i++;
  }
  return out.join('\n');
}

bool _looksLikeTableRow(String line) {
  final trimmed = line.trim();
  return trimmed.startsWith('|') && trimmed.indexOf('|', 1) != -1;
}

bool _isTableSeparator(String line) {
  if (!_looksLikeTableRow(line)) return false;
  final cells = _splitTableRow(line);
  if (cells.isEmpty) return false;
  // Every cell is just dashes with optional alignment colons (e.g. `:--:`).
  return cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c));
}

List<String> _splitTableRow(String line) {
  var trimmed = line.trim();
  if (trimmed.startsWith('|')) trimmed = trimmed.substring(1);
  if (trimmed.endsWith('|')) trimmed = trimmed.substring(0, trimmed.length - 1);
  return trimmed.split('|').map((c) => c.trim()).toList();
}

String _tableRowToBullet(List<String> headers, List<String> cells) {
  final parts = <String>[];
  for (var c = 0; c < cells.length; c++) {
    final value = cells[c];
    if (value.isEmpty) continue;
    if (parts.isEmpty) {
      parts.add('**$value**');
    } else {
      final label = c < headers.length ? headers[c] : '';
      parts.add(label.isEmpty ? value : '$label: $value');
    }
  }
  return parts.isEmpty ? '' : '- ${parts.join(' · ')}';
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
    // Outlined buttons sit on a muted fill (not transparent) so they still read
    // as a tappable control next to the one filled-accent primary.
    final bg = filled ? brand.accent : brand.surfaceMuted;
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
