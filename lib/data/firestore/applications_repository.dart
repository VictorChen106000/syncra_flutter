import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/job.dart';
import '../models/tracked_application.dart';
import 'firestore_paths.dart';

class ApplicationsRepository {
  ApplicationsRepository({FirebaseFirestore? db})
    : _paths = FirestorePaths(db ?? FirebaseFirestore.instance);

  final FirestorePaths _paths;

  Stream<List<TrackedApplication>> watchApplications(String uid) {
    return _paths
        .applications(uid)
        .orderBy('drafted_at', descending: true)
        .snapshots()
        .map(
          (snap) => dedupeOpenDraftApplicationsByJobId(
            snap.docs.map(_fromDoc).toList(growable: false),
          ),
        );
  }

  Future<TrackedApplication?> findOpenDraftByJobId({
    required String uid,
    required String jobId,
  }) async {
    final cleanJobId = jobId.trim();
    if (cleanJobId.isEmpty) return null;

    final snap = await _paths
        .applications(uid)
        .where('job.id', isEqualTo: cleanJobId)
        .get();

    return selectNewestOpenDraftApplicationByJobId(
      snap.docs.map(_fromDoc).toList(growable: false),
      cleanJobId,
    );
  }

  /// Agent creates a draft application. `sentAt` is null — the user must
  /// tap Send to mark it as actually submitted.
  Future<String> createApplication({
    required String uid,
    required Job job,
    String? resumeId,
    String trustRiskLevel = 'unchecked',
    String trustRiskLabel = 'Not checked',
    int trustSignalsCount = 0,
    List<Map<String, String>> trustSignals = const [],
    String trustSafeNextStep = '',
  }) async {
    final ref = _paths.applications(uid).doc();
    await ref.set({
      'job': _jobToMap(job),
      'resume_id': resumeId,
      'drafted_at': FieldValue.serverTimestamp(),
      'sent_at': null,
      'got_reply': false,
      'follow_up_at': null,
      'sent_email_id': null,
      'trust_risk_level': trustRiskLevel,
      'trust_risk_label': trustRiskLabel,
      'trust_signals_count': trustSignalsCount,
      'trust_signals': trustSignals,
      'trust_safe_next_step': trustSafeNextStep,
      'trust_checked_at': trustRiskLevel == 'unchecked'
          ? null
          : FieldValue.serverTimestamp(),
      'notes': <Map<String, dynamic>>[],
    });
    return ref.id;
  }

  Future<String> createOrReuseDraftApplication({
    required String uid,
    required Job job,
    String? resumeId,
    String trustRiskLevel = 'unchecked',
    String trustRiskLabel = 'Not checked',
    int trustSignalsCount = 0,
    List<Map<String, String>> trustSignals = const [],
    String trustSafeNextStep = '',
  }) async {
    final existing = await findOpenDraftByJobId(uid: uid, jobId: job.id);
    if (existing == null) {
      return createApplication(
        uid: uid,
        job: job,
        resumeId: resumeId,
        trustRiskLevel: trustRiskLevel,
        trustRiskLabel: trustRiskLabel,
        trustSignalsCount: trustSignalsCount,
        trustSignals: trustSignals,
        trustSafeNextStep: trustSafeNextStep,
      );
    }

    final cleanResumeId = resumeId?.trim();
    final trustPatch = _hasTrustGuardUpdate(
      trustRiskLevel: trustRiskLevel,
      trustRiskLabel: trustRiskLabel,
      trustSignalsCount: trustSignalsCount,
      trustSignals: trustSignals,
      trustSafeNextStep: trustSafeNextStep,
    );

    await _paths.applications(uid).doc(existing.id).update({
      'job': _jobToMap(job),
      if (cleanResumeId != null && cleanResumeId.isNotEmpty)
        'resume_id': cleanResumeId,
      if (trustPatch) ...{
        'trust_risk_level': trustRiskLevel,
        'trust_risk_label': trustRiskLabel,
        'trust_signals_count': trustSignalsCount,
        'trust_signals': trustSignals,
        'trust_safe_next_step': trustSafeNextStep,
        'trust_checked_at': trustRiskLevel == 'unchecked'
            ? null
            : FieldValue.serverTimestamp(),
      },
    });
    return existing.id;
  }

  /// User tapped Send (or the agent's `send_email` tool succeeded). Stamps
  /// `sent_at` and optionally records the Gmail message id.
  Future<void> markSent(
    String uid,
    String applicationId, {
    String? sentEmailId,
  }) async {
    await _paths.applications(uid).doc(applicationId).update({
      'sent_at': FieldValue.serverTimestamp(),
      'sent_email_id': ?sentEmailId,
    });
  }

  Future<int> countSentToday(String uid, {DateTime? now}) async {
    final anchor = now ?? DateTime.now();
    final start = DateTime(anchor.year, anchor.month, anchor.day);
    final end = start.add(const Duration(days: 1));
    final snap = await _paths
        .applications(uid)
        .where('sent_at', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('sent_at', isLessThan: Timestamp.fromDate(end))
        .get();
    return snap.docs.length;
  }

  Future<void> setGotReply(
    String uid,
    String applicationId,
    bool gotReply,
  ) async {
    await _paths.applications(uid).doc(applicationId).update({
      'got_reply': gotReply,
    });
  }

  Future<void> setFollowUp(
    String uid,
    String applicationId,
    DateTime? followUpAt,
  ) async {
    await _paths.applications(uid).doc(applicationId).update({
      'follow_up_at': followUpAt == null
          ? null
          : Timestamp.fromDate(followUpAt),
    });
  }

  Future<void> addNote(String uid, String applicationId, String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return;

    await _paths.applications(uid).doc(applicationId).update({
      'notes': FieldValue.arrayUnion([
        {
          'id': 'note_${DateTime.now().microsecondsSinceEpoch}',
          'body': trimmed,
          'created_at': Timestamp.now(),
        },
      ]),
    });
  }

  Future<void> updateNote(
    String uid,
    String applicationId,
    List<TrackedApplicationNote> currentNotes,
    String noteId,
    String body,
  ) async {
    final cleanId = noteId.trim();
    final trimmed = body.trim();
    if (cleanId.isEmpty || trimmed.isEmpty) return;

    final next = currentNotes
        .map((note) => note.id == cleanId ? note.copyWith(body: trimmed) : note)
        .map(_noteToMap)
        .toList(growable: false);

    await _paths.applications(uid).doc(applicationId).update({'notes': next});
  }

  Future<void> deleteNote(
    String uid,
    String applicationId,
    List<TrackedApplicationNote> currentNotes,
    String noteId,
  ) async {
    final cleanId = noteId.trim();
    if (cleanId.isEmpty) return;

    final next = currentNotes
        .where((note) => note.id != cleanId)
        .map(_noteToMap)
        .toList(growable: false);

    await _paths.applications(uid).doc(applicationId).update({'notes': next});
  }

  Future<void> setTrustGuard(
    String uid,
    String applicationId, {
    required String trustRiskLevel,
    required String trustRiskLabel,
    required int trustSignalsCount,
    required List<Map<String, String>> trustSignals,
    required String trustSafeNextStep,
  }) async {
    await _paths.applications(uid).doc(applicationId).update({
      'trust_risk_level': trustRiskLevel,
      'trust_risk_label': trustRiskLabel,
      'trust_signals_count': trustSignalsCount,
      'trust_signals': trustSignals,
      'trust_safe_next_step': trustSafeNextStep,
      'trust_checked_at': trustRiskLevel == 'unchecked'
          ? null
          : FieldValue.serverTimestamp(),
    });
  }
}

@visibleForTesting
TrackedApplication? selectNewestOpenDraftApplicationByJobId(
  List<TrackedApplication> applications,
  String jobId,
) {
  final cleanJobId = jobId.trim();
  if (cleanJobId.isEmpty) return null;

  TrackedApplication? best;
  for (final application in applications) {
    if (application.job.id.trim() != cleanJobId || application.sentAt != null) {
      continue;
    }

    if (best == null ||
        application.draftedAt.isAfter(best.draftedAt) ||
        (application.draftedAt == best.draftedAt &&
            application.id.compareTo(best.id) > 0)) {
      best = application;
    }
  }

  return best;
}

List<TrackedApplication> dedupeOpenDraftApplicationsByJobId(
  List<TrackedApplication> applications,
) {
  final result = <TrackedApplication>[];
  final openDraftsByJobId = <String, List<TrackedApplication>>{};

  for (final application in applications) {
    final jobId = application.job.id.trim();
    if (application.sentAt == null && jobId.isNotEmpty) {
      openDraftsByJobId
          .putIfAbsent(jobId, () => <TrackedApplication>[])
          .add(application);
    } else {
      result.add(application);
    }
  }

  for (final entry in openDraftsByJobId.entries) {
    final newest = selectNewestOpenDraftApplicationByJobId(
      entry.value,
      entry.key,
    );
    if (newest != null) result.add(newest);
  }

  return result..sort((a, b) {
    final byActivity = b.sortAt.compareTo(a.sortAt);
    if (byActivity != 0) return byActivity;
    return b.id.compareTo(a.id);
  });
}

TrackedApplication _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final data = doc.data();
  final job = _jobFromMap(Map<String, dynamic>.from(data['job'] as Map));

  return TrackedApplication(
    id: doc.id,
    job: job,
    resumeId: data['resume_id'] as String?,
    draftedAt: _toDate(data['drafted_at']) ?? DateTime.now(),
    sentAt: _toDate(data['sent_at']),
    gotReply: (data['got_reply'] as bool?) ?? false,
    followUpAt: _toDate(data['follow_up_at']),
    sentEmailId: data['sent_email_id'] as String?,
    trustRiskLevel: (data['trust_risk_level'] as String?) ?? 'unchecked',
    trustRiskLabel: (data['trust_risk_label'] as String?) ?? 'Not checked',
    trustSignalsCount: (data['trust_signals_count'] as num?)?.toInt() ?? 0,
    trustSignals: _trustSignalsFrom(data['trust_signals']),
    trustSafeNextStep: (data['trust_safe_next_step'] as String?) ?? '',
    notes: _notesFrom(data['notes']),
  );
}

List<Map<String, String>> _trustSignalsFrom(Object? value) {
  if (value is! List) return const [];

  final signals = <Map<String, String>>[];

  for (final raw in value.whereType<Map>()) {
    final severity = raw['severity']?.toString().trim() ?? '';
    final label = raw['label']?.toString().trim() ?? '';
    final detail = raw['detail']?.toString().trim() ?? '';

    if (label.isEmpty && detail.isEmpty) continue;

    signals.add({
      'severity': severity.isEmpty ? 'medium' : severity,
      'label': label.isEmpty ? 'Trust signal' : label,
      'detail': detail,
    });
  }

  return signals;
}

Job _jobFromMap(Map<String, dynamic> m) => Job(
  id: (m['id'] ?? '').toString(),
  title: (m['title'] as String?) ?? '',
  company: (m['company'] as String?) ?? '',
  location: (m['location'] as String?) ?? '',
  salary: (m['salary'] as String?) ?? '',
  category: _categoryFromName(m['category'] as String?),
  matchScore: (m['match_score'] as num?)?.toInt() ?? 0,
  agentAction: (m['agent_action'] as String?) ?? '',
  agentJustification: (m['agent_justification'] as String?) ?? '',
  skills: List<String>.from((m['skills'] as List?) ?? const []),
  missingSkills: List<String>.from((m['missing_skills'] as List?) ?? const []),
  why: (m['why'] as String?) ?? '',
);

Map<String, dynamic> _jobToMap(Job j) => {
  'id': j.id,
  'title': j.title,
  'company': j.company,
  'location': j.location,
  'salary': j.salary,
  'category': j.category.name,
  'match_score': j.matchScore,
  'agent_action': j.agentAction,
  'agent_justification': j.agentJustification,
  'skills': j.skills,
  'missing_skills': j.missingSkills,
  'why': j.why,
};

bool _hasTrustGuardUpdate({
  required String trustRiskLevel,
  required String trustRiskLabel,
  required int trustSignalsCount,
  required List<Map<String, String>> trustSignals,
  required String trustSafeNextStep,
}) {
  return trustRiskLevel != 'unchecked' ||
      trustRiskLabel != 'Not checked' ||
      trustSignalsCount > 0 ||
      trustSignals.isNotEmpty ||
      trustSafeNextStep.trim().isNotEmpty;
}

JobCategory _categoryFromName(String? name) {
  for (final c in JobCategory.values) {
    if (c.name == name) return c;
  }
  return JobCategory.ready;
}

List<TrackedApplicationNote> _notesFrom(Object? value) {
  if (value is! List) return const [];

  final notes = <TrackedApplicationNote>[];

  for (var i = 0; i < value.length; i++) {
    final raw = value[i];
    if (raw is! Map) continue;

    final createdAt = _toDate(raw['created_at']) ?? DateTime.now();
    final rawId = raw['id']?.toString().trim() ?? '';

    notes.add(
      TrackedApplicationNote(
        id: rawId.isEmpty
            ? 'legacy_${createdAt.millisecondsSinceEpoch}_$i'
            : rawId,
        body: raw['body']?.toString() ?? '',
        createdAt: createdAt,
      ),
    );
  }

  return notes;
}

Map<String, dynamic> _noteToMap(TrackedApplicationNote note) => {
  'id': note.id,
  'body': note.body,
  'created_at': Timestamp.fromDate(note.createdAt),
};

DateTime? _toDate(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
