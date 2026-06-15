import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/firestore/applications_repository.dart';
import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/pipeline_repository.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../../data/models/job.dart';
import '../../agent_chat/tools/anthropic_tool_calls.dart';
import '../../auth/models/user_profile.dart';
import '../../auth/state/auth_notifier.dart';
import '../../auth/state/user_profile_notifier.dart';
import '../../email/services/email_send_service.dart';
import '../../email/services/recipient_confidence_gate.dart';
import '../../email/services/recipient_resolver.dart';
import '../../jobs/state/jobs_notifier.dart';
import '../../resumes/models/proposed_edit.dart';
import '../../resumes/services/resume_parser_service.dart';
import '../../resumes/services/resume_tailor_orchestrator.dart';

/// How far the pipeline auto-processor carries a card, keyed off the user's
/// autonomy level. Pure so it can be unit-tested without Firestore/LLM.
/// - [AutonomyLevel.assist]: do nothing — the user drives every step.
/// - [AutonomyLevel.autoDraft]: tailor + draft, stop at the Drafted stage.
/// - [AutonomyLevel.autopilot]: also auto-send, advancing to Sent.
PipelineStage? pipelineAutopilotStopStage(AutonomyLevel level) =>
    switch (level) {
      AutonomyLevel.assist => null,
      AutonomyLevel.autoDraft => PipelineStage.drafted,
      AutonomyLevel.autopilot => PipelineStage.sent,
    };

/// The cards the auto-processor is allowed to touch: a fresh `matched` Strong
/// (`ready`) or Partial (`inputNeeded`) match. Only Stretch (`exploration`)
/// still waits for the user. Demo inbox routing is handled by the configured
/// demo email override inside the recipient resolver.
/// Partial matches tailor on real résumé facts only — the missing skill is
/// never invented. Pure + testable.
@visibleForTesting
List<PipelineCard> pipelineAutopilotCandidates(List<PipelineCard> cards) {
  return cards
      .where(
        (c) =>
            c.status == PipelineCardStatus.pending &&
            c.stage == PipelineStage.matched &&
            (c.job.category == JobCategory.ready ||
                c.job.category == JobCategory.inputNeeded),
      )
      .toList(growable: false);
}

@immutable
class PipelineAutopilotState {
  const PipelineAutopilotState({
    this.isProcessing = false,
    this.processedCount = 0,
  });

  /// True while a run is in flight — drives an optional "Syncra is preparing
  /// your applications…" banner on the pipeline.
  final bool isProcessing;

  /// How many cards this session's runs have carried forward. Cumulative.
  final int processedCount;

  PipelineAutopilotState copyWith({bool? isProcessing, int? processedCount}) {
    return PipelineAutopilotState(
      isProcessing: isProcessing ?? this.isProcessing,
      processedCount: processedCount ?? this.processedCount,
    );
  }
}

/// Foreground pipeline auto-processor. When the user opens the Pipeline on
/// Auto-draft or Autopilot, it walks the strong, low-risk `matched` cards and
/// carries each forward — tailor the résumé (headless), draft outreach, and on
/// Autopilot send it — advancing the card's stepper live as it goes.
///
/// Deliberately foreground and bounded: it never runs on Assist, only touches
/// strong + partial matched cards (never stretch), caps how many it processes
/// per run, and is idempotent (a job is processed at most once per session). The
/// irreversible send still goes through [EmailSendService.autoSend], which
/// mints its own one-shot token — the model never sends here.
class PipelineAutopilotNotifier extends Notifier<PipelineAutopilotState> {
  PipelineAutopilotNotifier({
    AnthropicParaphraseService? paraphrase,
    ResumeTailorOrchestrator? orchestrator,
    PipelineRepository? pipeline,
    ApplicationsRepository? applications,
    EmailSendService? emailSender,
  }) : _injectedParaphrase = paraphrase,
       _injectedOrchestrator = orchestrator,
       _injectedPipeline = pipeline,
       _injectedApplications = applications,
       _injectedEmailSender = emailSender;

  final AnthropicParaphraseService? _injectedParaphrase;
  final ResumeTailorOrchestrator? _injectedOrchestrator;
  final PipelineRepository? _injectedPipeline;
  final ApplicationsRepository? _injectedApplications;
  final EmailSendService? _injectedEmailSender;

  // Built lazily so merely constructing the notifier — when the Pipeline screen
  // first reads the provider, or in a widget test — touches no Firebase or
  // network. The real dependencies are created only once a run gets past its
  // guards and actually has work to do.
  late final AnthropicParaphraseService _paraphrase =
      _injectedParaphrase ?? AnthropicParaphraseService();
  late final ResumeTailorOrchestrator _orchestrator =
      _injectedOrchestrator ??
      ResumeTailorOrchestrator(
        resumesRepository: ResumesRepository(),
        jobsRepository: JobsRepository(),
        parser: ResumeParserService(),
      );
  late final PipelineRepository _pipeline =
      _injectedPipeline ?? PipelineRepository();
  late final ApplicationsRepository _applications =
      _injectedApplications ?? ApplicationsRepository();
  late final EmailSendService _emailSender =
      _injectedEmailSender ?? EmailSendService.instance;

  /// Hard cap per run so one pipeline can't fire a dozen tailor+draft+send
  /// chains at once (LLM cost + rate limits).
  static const int _maxPerRun = 5;

  /// Jobs already handled this session — keeps repeated [processNow] calls
  /// (the screen re-triggers as cards stream in) from reprocessing a card.
  final Set<String> _processedJobIds = {};

  bool _running = false;

  @override
  PipelineAutopilotState build() => const PipelineAutopilotState();

  /// Whether the autopilot has claimed [jobId] this session (processing it now
  /// or already done). The chat reads this so tapping a card mid-run shows
  /// "preparing…" instead of kicking off a duplicate tailor/draft on the same
  /// job. Cleared only by a fresh session (the set is per-notifier).
  bool isAutopilotHandling(String jobId) => _processedJobIds.contains(jobId);

  /// Kicks off a bounded auto-processing pass. Safe to call repeatedly — it
  /// no-ops while a run is in flight, on Assist, without an API key, or when
  /// there are no fresh candidates.
  Future<void> processNow() async {
    if (_running) return;

    final auth = ref.read(authProvider);
    final user = auth.appUser;
    if (user == null || user.isGuest) return;
    final uid = user.uid;

    final level =
        ref.read(userProfileProvider)?.autonomyLevel ?? AutonomyLevel.autoDraft;
    final stopStage = pipelineAutopilotStopStage(level);
    if (stopStage == null) return; // Assist — user drives every step.

    if (!_paraphrase.hasApiKey) return;

    final candidates = pipelineAutopilotCandidates(ref.read(jobsProvider).cards)
        .where((c) => !_processedJobIds.contains(c.job.id))
        .take(_maxPerRun)
        .toList();
    if (candidates.isEmpty) return;

    _running = true;
    state = state.copyWith(isProcessing: true);
    try {
      final sourceResumeId = await _orchestrator.latestManualResumeId(uid);
      if (sourceResumeId == null || sourceResumeId.isEmpty) return;

      // Claim every candidate up front so a tap into the chat mid-run sees the
      // job as autopilot-owned ([isAutopilotHandling]) and the opener shows
      // "preparing…" instead of offering a duplicate "Prepare draft".
      for (final card in candidates) {
        _processedJobIds.add(card.job.id);
      }

      for (final card in candidates) {
        try {
          await _processCard(
            uid: uid,
            card: card,
            stopStage: stopStage,
            sourceResumeId: sourceResumeId,
          );
          state = state.copyWith(processedCount: state.processedCount + 1);
        } catch (e) {
          // Isolate failures: one bad card must not abort the rest of the run.
          debugPrint('pipeline autopilot: ${card.job.id} failed → $e');
        }
      }
    } catch (e) {
      debugPrint('pipeline autopilot run failed: $e');
    } finally {
      _running = false;
      state = state.copyWith(isProcessing: false);
    }
  }

  Future<void> _processCard({
    required String uid,
    required PipelineCard card,
    required PipelineStage stopStage,
    required String sourceResumeId,
  }) async {
    final job = card.job;
    final resumeJson = (await _orchestrator.readResumeJson(
      uid: uid,
      resumeId: sourceResumeId,
    )).toJson();

    // 1. Tailor — best-effort. If it yields edits, save the tailored copy and
    // attach it; otherwise the original résumé stands in.
    var attachmentResumeId = sourceResumeId;
    try {
      final tailorResult = await _paraphrase.tailorResume(
        resumeJson: resumeJson,
        job: job,
      );
      final edits = (tailorResult['proposed_edits'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => ProposedEdit.fromJson(m.cast<String, dynamic>()))
          .where((e) => e.isValid)
          .toList();
      if (edits.isNotEmpty) {
        final applied = await _orchestrator.applyEdits(
          uid: uid,
          resumeId: sourceResumeId,
          acceptedEdits: edits,
          jobId: job.id,
        );
        attachmentResumeId = applied.file.id;
      }
    } catch (e) {
      debugPrint('pipeline autopilot: tailor failed for ${job.id} → $e');
    }
    await _pipeline.advanceStage(
      uid: uid,
      jobId: job.id,
      stage: PipelineStage.tailored,
    );

    // 2. Draft outreach.
    final draft = await _paraphrase.draftColdEmail(
      resumeJson: resumeJson,
      job: job,
    );
    final subject = (draft['subject'] as String?)?.trim() ?? '';
    final body = (draft['body'] as String?)?.trim() ?? '';
    await _pipeline.advanceStage(
      uid: uid,
      jobId: job.id,
      stage: PipelineStage.drafted,
    );

    // Auto-draft stops here — the user reviews and taps Send.
    if (stopStage != PipelineStage.sent) return;
    if (subject.isEmpty || body.isEmpty) return;

    // 3. Autopilot send. Resolve the recipient with the employer website when
    // available, then enforce the Recipient Confidence Gate. Confirmed/high
    // recipients may send; guessed/uncertain/missing recipients stop at the
    // drafted stage for user review.
    final resolution = await resolveRecipientAsync(
      job.company,
      website: job.employerWebsite,
    );
    final recipient = resolution.email;
    if (!_looksLikeEmail(recipient)) return;

    final gate = evaluateRecipientGate(resolution);
    if (!gate.canAutoSend) {
      debugPrint(
        'pipeline autopilot: stopped at draft for ${job.id} → ${gate.reason}',
      );
      return;
    }

    final appId = await _applications.createApplication(
      uid: uid,
      job: job,
      resumeId: attachmentResumeId,
    );

    await _emailSender.autoSend(
      to: recipient,
      subject: subject,
      body: body,
      recipientResolution: resolution,
      uid: uid,
      applicationId: appId,
      company: job.company,
    );

    // markSent on the application is handled inside autoSend; advancing to
    // `sent` also completes (approves) the pipeline card so it leaves the
    // active queue and lands in the tracker.
    await _pipeline.advanceStage(
      uid: uid,
      jobId: job.id,
      stage: PipelineStage.sent,
    );
  }
}

bool _looksLikeEmail(String value) {
  final v = value.trim();
  return v.contains('@') && v.contains('.') && !v.contains(' ');
}

final pipelineAutopilotProvider =
    NotifierProvider<PipelineAutopilotNotifier, PipelineAutopilotState>(
      PipelineAutopilotNotifier.new,
    );
