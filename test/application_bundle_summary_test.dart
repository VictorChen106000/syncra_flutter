import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/data/models/tracked_application.dart';
import 'package:syncra/features/applications/services/application_bundle_summary.dart';

void main() {
  group('Application bundle summary', () {
    test('marks a low-risk sent application with a resume as ready', () {
      final bundle = evaluateApplicationBundle(
        _application(
          resumeId: 'resume_1',
          sentAt: DateTime(2026, 6, 5, 10),
          trustRiskLevel: 'low',
        ),
      );

      expect(bundle.completeCount, bundle.totalCount);
      expect(bundle.hasBlocker, isFalse);
      expect(bundle.statusLabel, 'Ready bundle');
      expect(
        bundle.items.map((item) => item.label),
        containsAll(['Resume', 'Email', 'Trust', 'Quality']),
      );
    });

    test('blocks the bundle when no resume is attached', () {
      final bundle = evaluateApplicationBundle(
        _application(
          resumeId: null,
          sentAt: DateTime(2026, 6, 5, 10),
          trustRiskLevel: 'low',
        ),
      );

      expect(bundle.hasBlocker, isTrue);
      expect(bundle.statusLabel, 'Needs review');

      final resume = bundle.items.firstWhere((item) => item.label == 'Resume');
      expect(resume.isComplete, isFalse);
      expect(resume.isBlocking, isTrue);
      expect(resume.detail, 'Attach a resume');
    });

    test('blocks the bundle for high-risk applications', () {
      final bundle = evaluateApplicationBundle(
        _application(
          resumeId: 'resume_1',
          sentAt: DateTime(2026, 6, 5, 10),
          trustRiskLevel: 'high',
        ),
      );

      expect(bundle.hasBlocker, isTrue);
      expect(bundle.statusLabel, 'Needs review');

      final trust = bundle.items.firstWhere((item) => item.label == 'Trust');
      expect(trust.isComplete, isFalse);
      expect(trust.isBlocking, isTrue);
      expect(trust.detail, 'Blocked');
    });

    test('keeps drafted applications in the email bundle item', () {
      final bundle = evaluateApplicationBundle(
        _application(resumeId: 'resume_1', trustRiskLevel: 'low'),
      );

      final email = bundle.items.firstWhere((item) => item.label == 'Email');
      expect(email.isComplete, isTrue);
      expect(email.detail, 'Draft ready');
    });
  });
}

TrackedApplication _application({
  String? resumeId = 'resume_1',
  DateTime? sentAt,
  String trustRiskLevel = 'low',
}) {
  return TrackedApplication(
    id: 'app_1',
    job: const Job(
      id: 'job_1',
      title: 'Flutter Developer',
      company: 'Syncra',
      location: 'Remote',
      salary: '',
      category: JobCategory.ready,
      matchScore: 0,
      agentAction: '',
      agentJustification: '',
      skills: ['Flutter', 'Firebase'],
      missingSkills: [],
      why: 'Build AI career tools.',
    ),
    resumeId: resumeId,
    draftedAt: DateTime(2026, 6, 5, 9),
    sentAt: sentAt,
    trustRiskLevel: trustRiskLevel,
    trustRiskLabel: _trustLabel(trustRiskLevel),
  );
}

String _trustLabel(String level) => switch (level) {
  'high' => 'High risk',
  'medium' => 'Needs verification',
  'low' => 'Looks normal',
  _ => 'Not checked',
};
