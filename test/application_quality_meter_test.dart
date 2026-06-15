import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/firestore/pipeline_repository.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/data/models/tracked_application.dart';
import 'package:syncra/features/jobs/services/application_quality_meter.dart';

void main() {
  group('Application Quality Meter', () {
    test('marks a low-risk drafted strong fit as ready', () {
      final result = evaluateApplicationQuality(
        _card(
          category: JobCategory.ready,
          trustRiskLevel: 'low',
          stage: PipelineStage.drafted,
        ),
      );

      // base 35 + ready 25 + low trust 20 + no-missing 15 + drafted 16 = 111 -> 100.
      expect(result.score, 100);
      expect(result.label, 'Application quality · Ready');
      expect(result.reasons, contains('Trust looks okay'));
      expect(result.reasons, contains('Resume fit strong'));
      expect(result.reasons, contains('Draft ready'));
    });

    test('caps unchecked jobs below ready even when otherwise strong', () {
      final result = evaluateApplicationQuality(
        _card(category: JobCategory.ready, stage: PipelineStage.drafted),
      );

      // Raw score is 99, but unchecked trust caps quality at 74.
      expect(result.score, 74);
      expect(result.label, 'Application quality · Needs polish');
      expect(result.reasons, contains('Trust not checked'));
    });

    test('caps medium-risk jobs below the send threshold', () {
      final result = evaluateApplicationQuality(
        _card(
          category: JobCategory.ready,
          trustRiskLevel: 'medium',
          stage: PipelineStage.drafted,
        ),
      );

      expect(result.score, 59);
      expect(result.label, 'Application quality · Needs info');
      expect(result.reasons, contains('Verify trust first'));
    });

    test('caps high-risk jobs as blocked', () {
      final result = evaluateApplicationQuality(
        _card(
          category: JobCategory.ready,
          trustRiskLevel: 'high',
          stage: PipelineStage.drafted,
        ),
      );

      expect(result.score, 35);
      expect(result.label, 'Application quality · Blocked');
      expect(result.reasons, contains('Trust blocked'));
    });

    test('explains missing skills for incomplete matches', () {
      final result = evaluateApplicationQuality(
        _card(
          category: JobCategory.inputNeeded,
          trustRiskLevel: 'low',
          stage: PipelineStage.drafted,
          missingSkills: const ['Web3', 'GraphQL'],
        ),
      );

      // base 35 + inputNeeded 14 + low trust 20 - missing(2*5=10) + drafted 16 = 75.
      expect(result.score, 75);
      expect(result.label, 'Application quality · Needs polish');
      expect(result.reasons, contains('Needs missing info'));
      expect(result.reasons, contains('Missing Web3, GraphQL'));
    });
  });

  test('evaluates tracked applications using their current phase', () {
    final result = evaluateTrackedApplicationQuality(
      _trackedApplication(phase: ApplicationPhase.sent, trustRiskLevel: 'low'),
    );

    // base 35 + ready 25 + low trust 20 + no-missing 15 + sent 18 = 113 -> 100.
    expect(result.score, 100);
    expect(result.label, 'Application quality · Ready');
    expect(result.reasons, contains('Trust looks okay'));
    expect(result.reasons, contains('Already sent'));
  });
}

PipelineCard _card({
  JobCategory category = JobCategory.ready,
  String trustRiskLevel = 'unchecked',
  PipelineStage stage = PipelineStage.matched,
  List<String> missingSkills = const [],
}) {
  return PipelineCard(
    id: 'card_1',
    status: PipelineCardStatus.pending,
    createdAt: DateTime(2026, 6, 5),
    stage: stage,
    trustRiskLevel: trustRiskLevel,
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
  );
}

TrackedApplication _trackedApplication({
  ApplicationPhase phase = ApplicationPhase.draft,
  String trustRiskLevel = 'unchecked',
}) {
  final draftedAt = DateTime(2026, 6, 5, 9);
  final sentAt = switch (phase) {
    ApplicationPhase.draft => null,
    ApplicationPhase.sent ||
    ApplicationPhase.replied => DateTime(2026, 6, 5, 10),
  };

  return TrackedApplication(
    id: 'app_1',
    job: _card().job,
    draftedAt: draftedAt,
    sentAt: sentAt,
    gotReply: phase == ApplicationPhase.replied,
    trustRiskLevel: trustRiskLevel,
    trustRiskLabel: _trustLabel(trustRiskLevel),
  );
}

String _trustLabel(String riskLevel) {
  return switch (riskLevel) {
    'low' => 'Looks okay',
    'medium' => 'Verify first',
    'high' => 'Blocked',
    _ => 'Not checked',
  };
}
