import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/data/models/tracked_application.dart';
import 'package:syncra/features/applications/services/auto_apply_eligibility.dart';
import 'package:syncra/features/auth/models/user_profile.dart';

void main() {
  group('Auto-apply eligibility', () {
    test('keeps auto-apply disabled by default', () {
      final result = evaluateAutoApplyEligibility(
        app: _application(),
        settings: const AutoApplySettings(),
        sentToday: 0,
      );

      expect(result.isEligible, isFalse);
      expect(result.statusLabel, 'Auto-apply is off');
      expect(result.reasons, contains('Auto-apply is off'));
    });

    test('allows a ready draft when all bounded rules pass', () {
      final result = evaluateAutoApplyEligibility(
        app: _application(),
        settings: const AutoApplySettings(enabled: true),
        sentToday: 0,
      );

      expect(result.isEligible, isTrue);
      expect(result.statusLabel, 'Ready for bounded auto-apply');
      expect(result.reasons, isEmpty);
      expect(result.qualityScore, 100);
    });

    test('blocks when the daily limit has already been reached', () {
      final result = evaluateAutoApplyEligibility(
        app: _application(),
        settings: const AutoApplySettings(
          enabled: true,
          maxDailyApplications: 2,
        ),
        sentToday: 2,
      );

      expect(result.isEligible, isFalse);
      expect(result.reasons, contains('Daily limit reached'));
    });

    test('blocks high-risk applications even if other inputs exist', () {
      final result = evaluateAutoApplyEligibility(
        app: _application(trustRiskLevel: 'high'),
        settings: const AutoApplySettings(enabled: true),
        sentToday: 0,
      );

      expect(result.isEligible, isFalse);
      expect(result.reasons, contains('Trust must be low risk'));
      expect(result.reasons, contains('Bundle needs review'));
      expect(result.reasons, contains('Trust: Blocked'));
    });

    test('blocks applications with incomplete bundles', () {
      final result = evaluateAutoApplyEligibility(
        app: _application(resumeId: null),
        settings: const AutoApplySettings(enabled: true),
        sentToday: 0,
      );

      expect(result.isEligible, isFalse);
      expect(result.reasons, contains('Bundle needs review'));
      expect(result.reasons, contains('Resume: Attach a resume'));
    });

    test('blocks applications below the configured quality threshold', () {
      final result = evaluateAutoApplyEligibility(
        app: _application(
          category: JobCategory.exploration,
          missingSkills: const ['Kubernetes', 'GraphQL', 'Web3'],
        ),
        settings: const AutoApplySettings(enabled: true),
        sentToday: 0,
      );

      expect(result.isEligible, isFalse);
      expect(result.qualityScore, 62);
      expect(result.reasons, contains('Quality 62% is below 85% minimum'));
    });

    test('blocks applications that are already sent', () {
      final result = evaluateAutoApplyEligibility(
        app: _application(sentAt: DateTime(2026, 6, 5, 10)),
        settings: const AutoApplySettings(enabled: true),
        sentToday: 0,
      );

      expect(result.isEligible, isFalse);
      expect(result.reasons, contains('Application is already sent'));
    });
  });
}

TrackedApplication _application({
  String? resumeId = 'resume_1',
  String trustRiskLevel = 'low',
  DateTime? sentAt,
  JobCategory category = JobCategory.ready,
  List<String> missingSkills = const [],
}) {
  return TrackedApplication(
    id: 'app_1',
    job: Job(
      id: 'job_1',
      title: 'Flutter Developer',
      company: 'Syncra',
      location: 'Remote',
      salary: '',
      category: category,
      matchScore: 0,
      agentAction: '',
      agentJustification: '',
      skills: const ['Flutter', 'Firebase'],
      missingSkills: missingSkills,
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
