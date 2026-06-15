import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/firestore/applications_repository.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/data/models/tracked_application.dart';

void main() {
  group('open draft application dedupe', () {
    test('selects the newest open draft for a job id', () {
      final sent = _app(
        id: 'sent',
        jobId: 'job_shared',
        sentAt: DateTime(2026, 6, 5, 11),
      );
      final older = _app(
        id: 'older',
        jobId: 'job_shared',
        draftedAt: DateTime(2026, 6, 5, 9),
      );
      final newest = _app(
        id: 'newest',
        jobId: 'job_shared',
        draftedAt: DateTime(2026, 6, 5, 10),
      );

      expect(
        selectNewestOpenDraftApplicationByJobId([
          sent,
          older,
          newest,
        ], 'job_shared')?.id,
        'newest',
      );
    });

    test('dedupes duplicate open drafts by exact job id', () {
      final sharedOlder = _app(
        id: 'shared_older',
        jobId: 'job_shared',
        draftedAt: DateTime(2026, 6, 5, 9),
      );
      final sharedNewer = _app(
        id: 'shared_newer',
        jobId: 'job_shared',
        draftedAt: DateTime(2026, 6, 5, 10),
      );
      final distinct = _app(id: 'distinct', jobId: 'job_distinct');

      final deduped = dedupeOpenDraftApplicationsByJobId([
        sharedOlder,
        sharedNewer,
        distinct,
      ]);

      expect(deduped.map((app) => app.id), ['shared_newer', 'distinct']);
    });

    test('keeps sent applications alongside open drafts for the same job', () {
      final draft = _app(
        id: 'draft',
        jobId: 'job_shared',
        draftedAt: DateTime(2026, 6, 5, 10),
      );
      final sent = _app(
        id: 'sent',
        jobId: 'job_shared',
        draftedAt: DateTime(2026, 6, 5, 9),
        sentAt: DateTime(2026, 6, 5, 11),
      );

      final deduped = dedupeOpenDraftApplicationsByJobId([draft, sent]);

      expect(deduped.map((app) => app.id), ['sent', 'draft']);
    });
  });
}

TrackedApplication _app({
  required String id,
  required String jobId,
  DateTime? draftedAt,
  DateTime? sentAt,
}) {
  return TrackedApplication(
    id: id,
    job: _job(id: jobId),
    resumeId: 'resume_1',
    draftedAt: draftedAt ?? DateTime(2026, 6, 5),
    sentAt: sentAt,
    trustRiskLevel: 'low',
    trustRiskLabel: 'Looks normal',
  );
}

Job _job({required String id}) {
  return Job(
    id: id,
    title: 'Product Designer',
    company: 'Acme',
    location: 'Remote',
    salary: '',
    category: JobCategory.ready,
    matchScore: 0,
    agentAction: '',
    agentJustification: '',
    skills: const [],
    missingSkills: const [],
    why:
        'A normal role description for testing application repository helpers.',
  );
}
