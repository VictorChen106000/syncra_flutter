import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/data/models/tracked_application.dart';
import 'package:syncra/features/applications/services/autopilot_safety_gate.dart';
import 'package:syncra/features/auth/models/user_profile.dart';
import 'package:syncra/features/email/models/recipient_resolution.dart';

void main() {
  group('evaluateAutopilotSendSafety', () {
    test('allows Autopilot when every safety gate passes', () {
      final decision = evaluateAutopilotSendSafety(
        autonomyLevel: AutonomyLevel.autopilot,
        settings: fixedAutoApplySettingsFor(AutonomyLevel.autopilot),
        application: _application(),
        sentToday: 0,
        recipient: _confirmedRecipient(),
      );

      expect(decision.allowed, isTrue);
      expect(decision.reasons, isEmpty);
    });

    test('blocks when autonomy is not Autopilot', () {
      final decision = evaluateAutopilotSendSafety(
        autonomyLevel: AutonomyLevel.autoDraft,
        settings: fixedAutoApplySettingsFor(AutonomyLevel.autoDraft),
        application: _application(),
        sentToday: 0,
        recipient: _confirmedRecipient(),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reasons, contains('Autopilot is not enabled'));
      expect(decision.reasons, contains('Auto-apply is off'));
      expect(decision.reasons, contains('Auto-send outreach is off'));
    });

    test('blocks already sent applications', () {
      final decision = _decision(
        application: _application(sentAt: DateTime.now()),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reasons, contains('Application is already sent'));
    });

    test('blocks when the daily limit is reached', () {
      final decision = _decision(sentToday: 3);

      expect(decision.allowed, isFalse);
      expect(decision.reasons, contains('Daily limit reached'));
    });

    test('blocks unchecked, medium, and high trust', () {
      for (final risk in ['unchecked', 'medium', 'high']) {
        final decision = _decision(
          application: _application(trustRiskLevel: risk),
        );

        expect(decision.allowed, isFalse, reason: risk);
        expect(decision.reasons, contains('Trust is not low-risk'));
        expect(
          decision.reasons,
          contains('Application bundle needs review'),
          reason: risk,
        );
      }
    });

    test('blocks quality below the hidden threshold', () {
      final decision = _decision(
        application: _application(
          category: JobCategory.exploration,
          missingSkills: const ['Kubernetes', 'GraphQL', 'Web3'],
        ),
      );

      expect(decision.allowed, isFalse);
      expect(decision.reasons, contains('Quality 62% is below 85% minimum'));
    });

    test('blocks incomplete application bundles', () {
      final decision = _decision(application: _application(resumeId: null));

      expect(decision.allowed, isFalse);
      expect(decision.reasons, contains('Application bundle needs review'));
    });

    test('blocks guessed, missing, and confirmation-required recipients', () {
      final recipients = [
        RecipientResolution.guessed(
          email: 'careers@example.com',
          domain: 'example.com',
        ),
        RecipientResolution.none(domain: 'example.com'),
        const RecipientResolution(
          email: 'talent@example.com',
          domain: 'example.com',
          confidence: RecipientConfidence.high,
          source: RecipientSource.officialCompanyWebsite,
          label: 'Found on official site',
          reason: 'Found, but user confirmation is still required.',
          canAutoSend: true,
          requiresUserConfirmation: true,
        ),
      ];

      for (final recipient in recipients) {
        final decision = _decision(recipient: recipient);

        expect(decision.allowed, isFalse, reason: recipient.source.name);
        expect(decision.reasons, contains('Recipient is not confirmed'));
      }
    });
  });
}

AutopilotSafetyDecision _decision({
  TrackedApplication? application,
  int sentToday = 0,
  RecipientResolution? recipient,
}) {
  return evaluateAutopilotSendSafety(
    autonomyLevel: AutonomyLevel.autopilot,
    settings: fixedAutoApplySettingsFor(AutonomyLevel.autopilot),
    application: application ?? _application(),
    sentToday: sentToday,
    recipient: recipient ?? _confirmedRecipient(),
  );
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

RecipientResolution _confirmedRecipient() => RecipientResolution.confirmed(
  email: 'talent@example.com',
  domain: 'example.com',
);

String _trustLabel(String level) => switch (level) {
  'high' => 'High risk',
  'medium' => 'Needs verification',
  'low' => 'Looks normal',
  _ => 'Not checked',
};
