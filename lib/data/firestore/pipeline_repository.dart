import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/job.dart';
import 'firestore_paths.dart';

enum PipelineCardStatus { pending, approved, dismissed }

/// How far the agent has carried a job along the apply pipeline. Advanced by
/// the agent tools as they complete: tailor_resume → [tailored],
/// draft_email → [drafted], a confirmed send → [sent]. This is the per-card
/// *progress* axis the Pipeline screen renders as a stepper.
enum PipelineStage { matched, tailored, drafted, sent, replied }

class PipelineCard {
  const PipelineCard({
    required this.id,
    required this.job,
    required this.status,
    required this.createdAt,
    this.stage = PipelineStage.matched,
  });

  final String id;
  final Job job;
  final PipelineCardStatus status;
  final DateTime createdAt;

  /// Current pipeline stage. Defaults to [PipelineStage.matched] for cards
  /// written before the `stage` field existed, so old data still renders.
  final PipelineStage stage;

  /// Terminal stages — the agent (or user) already sent this one.
  bool get isSent =>
      stage == PipelineStage.sent || stage == PipelineStage.replied;

  /// True when the card is waiting on the user. Orthogonal to [stage]: a
  /// finished draft needs a review-and-send tap, and an early match the agent
  /// flagged is missing info or needs a call. Sent cards never need you.
  bool get needsYou {
    if (isSent) return false;
    if (stage == PipelineStage.drafted) return true;
    return job.category == JobCategory.inputNeeded ||
        job.category == JobCategory.exploration;
  }
}

class PipelineRepository {
  PipelineRepository({FirebaseFirestore? db})
    : _paths = FirestorePaths(db ?? FirebaseFirestore.instance);

  final FirestorePaths _paths;

  Stream<List<PipelineCard>> watchPending(String uid) {
    return _paths
        .pipeline(uid)
        .orderBy('created_at', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map(_fromDoc)
              .where(shouldShowInActivePipeline)
              .toList(growable: false),
        );
  }

  Future<List<PipelineCard>> fetchPending(String uid, {int limit = 40}) async {
    final snap = await _paths
        .pipeline(uid)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();

    return snap.docs
        .map(_fromDoc)
        .where(shouldShowInActivePipeline)
        .toList(growable: false);
  }

  Future<void> dismiss(String uid, String cardId) {
    return _paths.pipeline(uid).doc(cardId).update({'status': 'dismissed'});
  }

  Future<void> approve(String uid, String cardId) {
    return _paths.pipeline(uid).doc(cardId).update({'status': 'approved'});
  }

  Future<void> approveByJobId({
    required String uid,
    required String jobId,
  }) async {
    final cleanJobId = jobId.trim();
    if (cleanJobId.isEmpty) return;

    final snap = await _paths
        .pipeline(uid)
        .where('job.id', isEqualTo: cleanJobId)
        .get();

    for (final doc in snap.docs) {
      await doc.reference.update({'status': 'approved'});
    }
  }

  /// Moves the pipeline card(s) for [jobId] forward to [stage] — this is what
  /// makes the stepper on the Pipeline screen actually progress as the agent
  /// (or user) tailors, drafts, and sends. Forward-only: a card already at or
  /// past [stage] is left untouched, so re-running a tool never rewinds the
  /// dots. No-op when the job has no pipeline card (e.g. a draft fired straight
  /// from chat without saving the role first). Best-effort by design — callers
  /// wrap it so a write hiccup never breaks the underlying tool.
  Future<void> advanceStage({
    required String uid,
    required String jobId,
    required PipelineStage stage,
  }) async {
    final cleanJobId = jobId.trim();
    if (cleanJobId.isEmpty) return;

    final snap = await _paths
        .pipeline(uid)
        .where('job.id', isEqualTo: cleanJobId)
        .get();
    if (snap.docs.isEmpty) return;

    for (final doc in snap.docs) {
      final current = _stageFromName(doc.data()['stage'] as String?);
      final patch = pipelineStagePatchFor(current: current, target: stage);

      if (patch.isEmpty) continue;

      await doc.reference.update(patch);
    }
  }

  Future<void> createCard({
    required String uid,
    required Job job,
    required JobCategory category,
    required int matchScore,
    required String agentAction,
    required String agentJustification,
    required List<String> matchedSkills,
    required List<String> missingSkills,
  }) async {
    await _paths.pipeline(uid).doc().set({
      'job': {
        'id': job.id,
        'title': job.title,
        'company': job.company,
        'location': job.location,
        'salary': job.salary,
        'employer_website': job.employerWebsite,
        'apply_link': job.applyLink,
        'google_job_link': job.googleJobLink,
        'source_url': job.sourceUrl,
        'publisher': job.publisher,
        'provider_source': job.providerSource,
      },
      'category': _categoryToName(category),
      'match_score': matchScore,
      'agent_action': agentAction,
      'agent_justification': agentJustification,
      'matched_skills': matchedSkills,
      'missing_skills': missingSkills,
      'why': job.why,
      'status': 'pending',
      'created_at': FieldValue.serverTimestamp(),
    });
  }
}

/// CRITICAL PIPELINE INVARIANT:
/// The active Jobs pipeline must only show unfinished pending work.
///
/// Cards that reached [PipelineStage.sent] or [PipelineStage.replied] are
/// already handled and must leave the active pipeline even if legacy Firestore
/// data still says `status: pending`.
///
/// Do not weaken this without updating:
/// - test/pipeline_repository_test.dart
/// - docs/ARCHITECTURE.md pipeline lifecycle notes
@visibleForTesting
bool shouldShowInActivePipeline(PipelineCard card) {
  return card.status == PipelineCardStatus.pending && !card.isSent;
}

/// CRITICAL PIPELINE INVARIANT:
/// Advancing a card to `sent` or `replied` completes the pipeline card by
/// writing `status: approved`. This prevents handled jobs from reappearing in
/// the active Jobs pipeline after refresh/restart.
@visibleForTesting
Map<String, dynamic> pipelineStagePatchFor({
  required PipelineStage current,
  required PipelineStage target,
}) {
  final shouldAdvanceStage = _stageRank(current) < _stageRank(target);
  final completesPipeline =
      target == PipelineStage.sent || target == PipelineStage.replied;

  if (!shouldAdvanceStage && !completesPipeline) {
    return const {};
  }

  return {
    if (shouldAdvanceStage) 'stage': _stageToName(target),
    if (completesPipeline) 'status': 'approved',
  };
}

String _categoryToName(JobCategory c) => switch (c) {
  JobCategory.ready => 'ready',
  JobCategory.inputNeeded => 'input_needed',
  JobCategory.exploration => 'exploration',
};

PipelineCard _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  final jobMap = Map<String, dynamic>.from((data['job'] as Map?) ?? const {});
  return PipelineCard(
    id: doc.id,
    job: Job(
      id: (jobMap['id'] ?? doc.id).toString(),
      title: (jobMap['title'] as String?) ?? '',
      company: (jobMap['company'] as String?) ?? '',
      location: (jobMap['location'] as String?) ?? '',
      salary: (jobMap['salary'] as String?) ?? '',
      category: _categoryFromName(data['category'] as String?),
      matchScore: (data['match_score'] as num?)?.toInt() ?? 0,
      agentAction: (data['agent_action'] as String?) ?? '',
      agentJustification: (data['agent_justification'] as String?) ?? '',
      skills: List<String>.from((data['matched_skills'] as List?) ?? const []),
      missingSkills: List<String>.from(
        (data['missing_skills'] as List?) ?? const [],
      ),
      why: (data['why'] as String?) ?? '',
      employerWebsite: (jobMap['employer_website'] as String?) ?? '',
      applyLink: (jobMap['apply_link'] as String?) ?? '',
      googleJobLink: (jobMap['google_job_link'] as String?) ?? '',
      sourceUrl: (jobMap['source_url'] as String?) ?? '',
      publisher: (jobMap['publisher'] as String?) ?? '',
      providerSource: (jobMap['provider_source'] as String?) ?? '',
    ),
    status: _statusFromName(data['status'] as String?),
    stage: _stageFromName(data['stage'] as String?),
    createdAt: _toDate(data['created_at']) ?? DateTime.now(),
  );
}

PipelineStage _stageFromName(String? name) => switch (name) {
  'tailored' => PipelineStage.tailored,
  'drafted' => PipelineStage.drafted,
  'sent' => PipelineStage.sent,
  'replied' => PipelineStage.replied,
  _ => PipelineStage.matched,
};

String _stageToName(PipelineStage stage) => switch (stage) {
  PipelineStage.matched => 'matched',
  PipelineStage.tailored => 'tailored',
  PipelineStage.drafted => 'drafted',
  PipelineStage.sent => 'sent',
  PipelineStage.replied => 'replied',
};

/// Linear order of the stepper, so [PipelineRepository.advanceStage] only ever
/// moves a card forward.
int _stageRank(PipelineStage stage) => switch (stage) {
  PipelineStage.matched => 0,
  PipelineStage.tailored => 1,
  PipelineStage.drafted => 2,
  PipelineStage.sent => 3,
  PipelineStage.replied => 4,
};

PipelineCardStatus _statusFromName(String? name) => switch (name) {
  'approved' => PipelineCardStatus.approved,
  'dismissed' => PipelineCardStatus.dismissed,
  _ => PipelineCardStatus.pending,
};

JobCategory _categoryFromName(String? name) => switch (name) {
  'input_needed' => JobCategory.inputNeeded,
  'exploration' => JobCategory.exploration,
  _ => JobCategory.ready,
};

DateTime? _toDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
