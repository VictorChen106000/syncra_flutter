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
  return _jobFromJobsDoc(doc.id, doc.data() ?? const {});
}

Job _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
  return _jobFromJobsDoc(doc.id, doc.data());
}

/// Builds a [Job] from a global `jobs/` document. Old docs predate the
/// apply/source provenance fields, so each defaults to `''`.
Job _jobFromJobsDoc(String id, Map<String, dynamic> m) {
  return Job(
    id: id,
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
    applyLink: (m['apply_link'] as String?) ?? '',
    googleJobLink: (m['google_job_link'] as String?) ?? '',
    sourceUrl: (m['source_url'] as String?) ?? '',
    publisher: (m['publisher'] as String?) ?? '',
    providerSource: (m['provider_source'] as String?) ?? '',
  );
}
