import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/firestore/jobs_repository.dart';
import '../../../data/firestore/resumes_repository.dart';
import '../../resumes/models/resume_json.dart';
import '../../resumes/services/resume_parser_service.dart';
import '../../resumes/services/resume_tailor_orchestrator.dart';
import '../../resumes/services/resume_tailor_service.dart';

/// What the onboarding flow knows about the user's resume right now.
///
/// Lives separately from [ResumeNotifier] so flipping in and out of onboarding
/// doesn't touch the shared resume selection state the regular chat relies on,
/// and so the (expensive) parse-to-JSON step only fires when onboarding
/// actually needs it.
@immutable
class OnboardingResumeContext {
  const OnboardingResumeContext({
    this.resume,
    this.resumeId,
    this.isLoading = false,
    this.failed = false,
    this.failureMessage,
  });

  /// Parsed canonical resume the agent's system prompt is grounded in. `null`
  /// before the user has uploaded/picked one, while parsing is in flight, or
  /// when ingestion failed.
  final ResumeJson? resume;

  /// Firestore id of the resume currently being ingested or already ingested.
  /// Used to dedupe re-ingestion of the same resume.
  final String? resumeId;

  /// True between the moment ingestion starts and the parse settling — drives
  /// the "reading your resume…" opener variant.
  final bool isLoading;

  /// True when ingestion failed (no text, parser error, etc.). The opener
  /// surfaces a fallback CTA in this state.
  final bool failed;

  /// Short user-facing reason for [failed], surfaced in the opener.
  final String? failureMessage;

  bool get hasResume => resume != null;
}

class OnboardingResumeContextNotifier
    extends Notifier<OnboardingResumeContext> {
  String? _ingestingId;

  @override
  OnboardingResumeContext build() => const OnboardingResumeContext();

  /// Kicks off the read-from-cache-or-parse pipeline for [resumeId] under
  /// the signed-in [uid]. No-op if the same resume id is already being
  /// ingested or has already been ingested successfully — this method is
  /// safe to call repeatedly from the onboarding page's `ref.listen`.
  Future<void> ingest({
    required String uid,
    required String resumeId,
  }) async {
    if (resumeId.isEmpty) return;
    if (_ingestingId == resumeId) return;
    if (state.resumeId == resumeId && state.hasResume) return;

    _ingestingId = resumeId;
    state = OnboardingResumeContext(
      resumeId: resumeId,
      isLoading: true,
    );

    try {
      // Reuse the tailor orchestrator's read path so we hit the same
      // Firestore JSON cache the rest of the agent already populates —
      // a second onboarding (or the first job tailoring step) won't have
      // to re-parse.
      final orchestrator = ResumeTailorOrchestrator(
        resumesRepository: ResumesRepository(),
        jobsRepository: JobsRepository(),
        parser: ResumeParserService(),
        tailor: ResumeTailorService(),
      );
      final parsed = await orchestrator.readResumeJson(
        uid: uid,
        resumeId: resumeId,
      );
      if (_ingestingId != resumeId) return;
      state = OnboardingResumeContext(
        resume: parsed,
        resumeId: resumeId,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('onboarding resume ingest failed: $e');
      if (_ingestingId != resumeId) return;
      state = OnboardingResumeContext(
        resumeId: resumeId,
        isLoading: false,
        failed: true,
        failureMessage: _shortError(e),
      );
    } finally {
      if (_ingestingId == resumeId) _ingestingId = null;
    }
  }

  /// Drops the ingested resume — called when the user signs out or leaves
  /// onboarding so the next entry starts clean.
  void reset() {
    _ingestingId = null;
    state = const OnboardingResumeContext();
  }

  String _shortError(Object e) {
    final raw = e
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('TailorOrchestratorException: ', '')
        .trim();
    if (raw.isEmpty) return "I couldn't read that resume.";
    return raw.length > 140 ? '${raw.substring(0, 140)}…' : raw;
  }
}

/// The resume the onboarding agent is grounded in. Both the
/// `agentServiceProvider` (which injects parsed resume context into the
/// system prompt) and the onboarding page's opener react to this.
final onboardingResumeContextProvider = NotifierProvider<
    OnboardingResumeContextNotifier, OnboardingResumeContext>(
  OnboardingResumeContextNotifier.new,
);
