import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/job.dart';
import 'firestore_paths.dart';

enum PipelineCardStatus { pending, approved, dismissed }

class PipelineCard {
  const PipelineCard({
    required this.id,
    required this.job,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final Job job;
  final PipelineCardStatus status;
  final DateTime createdAt;
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
        .map((snap) => snap.docs
            .map(_fromDoc)
            .where((card) => card.status == PipelineCardStatus.pending)
            .toList(growable: false));
  }

  Future<List<PipelineCard>> fetchPending(String uid, {int limit = 40}) async {
    final snap = await _paths
        .pipeline(uid)
        .orderBy('created_at', descending: true)
        .limit(limit)
        .get();

    return snap.docs
        .map(_fromDoc)
        .where((card) => card.status == PipelineCardStatus.pending)
        .toList(growable: false);
  }

  Future<void> dismiss(String uid, String cardId) {
    return _paths.pipeline(uid).doc(cardId).update({'status': 'dismissed'});
  }

  Future<void> approve(String uid, String cardId) {
    return _paths.pipeline(uid).doc(cardId).update({'status': 'approved'});
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
    ),
    status: _statusFromName(data['status'] as String?),
    createdAt: _toDate(data['created_at']) ?? DateTime.now(),
  );
}

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
