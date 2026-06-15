import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/job.dart';
import 'firestore_paths.dart';

/// Reads the global `jobs/` collection. Each doc is a raw posting
/// (title, company, location, salary, description, source_url) without
/// the pipeline-card agent fields.
class JobsRepository {
  JobsRepository({FirebaseFirestore? db})
    : _paths = FirestorePaths(db ?? FirebaseFirestore.instance);

  final FirestorePaths _paths;

  Future<List<Job>> fetchAll({int limit = 40}) async {
    final snap = await _paths.jobs().limit(limit).get();
    return snap.docs.map(_fromDoc).toList(growable: false);
  }

  Future<Job?> fetchById(String jobId) async {
    final snap = await _paths.jobs().doc(jobId).get();
    if (!snap.exists) return null;
    return _fromDocSnap(snap);
  }
}

Job _fromDocSnap(DocumentSnapshot<Map<String, dynamic>> doc) {
  final m = doc.data() ?? const {};
  return Job(
    id: doc.id,
    title: (m['title'] as String?) ?? '',
    company: (m['company'] as String?) ?? '',
    location: (m['location'] as String?) ?? '',
    salary: (m['salary'] as String?) ?? '',
    category: JobCategory.ready,
    matchScore: 0,
    agentAction: '',
    agentJustification: '',
    skills: const [],
    missingSkills: const [],
    why: (m['description'] as String?) ?? '',
    employerWebsite: (m['employer_website'] as String?) ?? '',
  );
}

Job _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  final m = doc.data();
  return Job(
    id: doc.id,
    title: (m['title'] as String?) ?? '',
    company: (m['company'] as String?) ?? '',
    location: (m['location'] as String?) ?? '',
    salary: (m['salary'] as String?) ?? '',
    category: JobCategory.ready,
    matchScore: 0,
    agentAction: '',
    agentJustification: '',
    skills: const [],
    missingSkills: const [],
    why: (m['description'] as String?) ?? '',
    employerWebsite: (m['employer_website'] as String?) ?? '',
  );
}
