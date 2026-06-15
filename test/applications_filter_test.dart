import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/data/models/tracked_application.dart';
import 'package:syncra/features/applications/state/applications_notifier.dart';

void main() {
  group('ApplicationsState filters', () {
    test('bundle review filter includes only applications with blockers', () {
      final missingResume = _app(
        id: 'missing_resume',
        company: 'No Resume Co',
        resumeId: null,
        trustRiskLevel: 'low',
        draftedAt: DateTime(2026, 6, 5, 12),
      );
      final highRisk = _app(
        id: 'high_risk',
        company: 'Risky Co',
        resumeId: 'resume_1',
        trustRiskLevel: 'high',
        draftedAt: DateTime(2026, 6, 5, 13),
      );
      final ready = _app(
        id: 'ready',
        company: 'Ready Co',
        resumeId: 'resume_1',
        trustRiskLevel: 'low',
        sentAt: DateTime(2026, 6, 5, 14),
      );

      final state = ApplicationsState(
        items: [missingResume, highRisk, ready],
        filter: ApplicationsFilter.bundleReview,
      );

      expect(state.filtered.map((app) => app.id), [
        'high_risk',
        'missing_resume',
      ]);
    });
    test(
      'trust review filter includes only medium and high risk applications',
      () {
        final high = _app(
          id: 'high',
          company: 'Risky Co',
          trustRiskLevel: 'high',
          draftedAt: DateTime(2026, 6, 5, 12),
        );
        final medium = _app(
          id: 'medium',
          company: 'Verify Co',
          trustRiskLevel: 'medium',
          draftedAt: DateTime(2026, 6, 5, 13),
        );
        final low = _app(
          id: 'low',
          company: 'Normal Co',
          trustRiskLevel: 'low',
          draftedAt: DateTime(2026, 6, 5, 14),
        );
        final unchecked = _app(
          id: 'unchecked',
          company: 'Old Co',
          trustRiskLevel: 'unchecked',
          draftedAt: DateTime(2026, 6, 5, 15),
        );

        final state = ApplicationsState(
          items: [high, medium, low, unchecked],
          filter: ApplicationsFilter.trustReview,
        );

        expect(state.filtered.map((app) => app.id), ['medium', 'high']);
      },
    );

    test('phase filters still return the expected application phases', () {
      final draft = _app(id: 'draft');
      final sent = _app(id: 'sent', sentAt: DateTime(2026, 6, 5, 10));
      final replied = _app(
        id: 'replied',
        sentAt: DateTime(2026, 6, 5, 10),
        gotReply: true,
      );

      final items = [draft, sent, replied];

      expect(
        ApplicationsState(
          items: items,
          filter: ApplicationsFilter.drafts,
        ).filtered.map((app) => app.id),
        ['draft'],
      );

      expect(
        ApplicationsState(
          items: items,
          filter: ApplicationsFilter.sent,
        ).filtered.map((app) => app.id),
        ['sent'],
      );

      expect(
        ApplicationsState(
          items: items,
          filter: ApplicationsFilter.replied,
        ).filtered.map((app) => app.id),
        ['replied'],
      );
    });

    test('all filter sorts applications by latest activity first', () {
      final oldest = _app(id: 'oldest', draftedAt: DateTime(2026, 6, 5, 9));
      final newestDraft = _app(
        id: 'newest_draft',
        draftedAt: DateTime(2026, 6, 5, 12),
      );
      final newestSent = _app(
        id: 'newest_sent',
        draftedAt: DateTime(2026, 6, 5, 8),
        sentAt: DateTime(2026, 6, 5, 13),
      );

      final state = ApplicationsState(items: [oldest, newestDraft, newestSent]);

      expect(state.filtered.map((app) => app.id), [
        'newest_sent',
        'newest_draft',
        'oldest',
      ]);
    });

    test('draft count and filters dedupe duplicate open drafts by job id', () {
      final older = _app(
        id: 'older',
        jobId: 'job_shared',
        draftedAt: DateTime(2026, 6, 5, 9),
      );
      final newer = _app(
        id: 'newer',
        jobId: 'job_shared',
        draftedAt: DateTime(2026, 6, 5, 10),
      );

      final state = ApplicationsState(
        items: [older, newer],
        filter: ApplicationsFilter.drafts,
      );

      expect(state.countOf(ApplicationPhase.draft), 1);
      expect(state.filtered.map((app) => app.id), ['newer']);
    });

    test('sent applications are not collapsed with open drafts', () {
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

      final state = ApplicationsState(items: [draft, sent]);

      expect(state.countOf(ApplicationPhase.draft), 1);
      expect(state.countOf(ApplicationPhase.sent), 1);
      expect(state.filtered.map((app) => app.id), ['sent', 'draft']);
    });

    test('trust review label is available for filter chips', () {
      expect(ApplicationsFilter.trustReview.label, 'Trust review');
    });
  });
}

TrackedApplication _app({
  required String id,
  String? jobId,
  String company = 'Acme',
  String? resumeId = 'resume_1',
  DateTime? draftedAt,
  DateTime? sentAt,
  bool gotReply = false,
  String trustRiskLevel = 'low',
}) {
  return TrackedApplication(
    id: id,
    resumeId: resumeId,
    job: _job(id: jobId ?? 'job_$id', company: company),
    draftedAt: draftedAt ?? DateTime(2026, 6, 5),
    sentAt: sentAt,
    gotReply: gotReply,
    trustRiskLevel: trustRiskLevel,
    trustRiskLabel: switch (trustRiskLevel) {
      'high' => 'High risk',
      'medium' => 'Needs verification',
      'low' => 'Looks normal',
      _ => 'Not checked',
    },
  );
}

Job _job({required String id, required String company}) {
  return Job(
    id: id,
    title: 'Product Designer',
    company: company,
    location: 'Remote',
    salary: '',
    category: JobCategory.ready,
    matchScore: 0,
    agentAction: '',
    agentJustification: '',
    skills: const [],
    missingSkills: const [],
    why: 'A normal role description for testing application filters.',
  );
}
