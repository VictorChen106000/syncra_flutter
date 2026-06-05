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

      expect(result.score, 100);
      expect(result.label, 'Application quality · Ready');
      expect(result.reasons, contains('Trust looks okay'));
      expect(result.reasons, contains('Resume fit strong'));
      expect(result.reasons, contains('Draft ready'));
    });

    test('caps unchecked legacy cards below ready', () {
      final result = evaluateApplicationQuality(
        _card(
          category: JobCategory.ready,
          trustRiskLevel: 'unchecked',
          stage: PipelineStage.drafted,
        ),
      );

      expect(result.score, 74);
      expect(result.label, 'Application quality · Needs polish');
      expect(result.reasons, contains('Trust not checked'));
    });

    test('caps medium-risk cards below polish even with a strong fit', () {
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

    test('blocks high-risk cards even when the resume fit is strong', () {
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
          missingSkills: const ['Web3', 'GraphQL', 'Kubernetes'],
        ),
      );

      expect(result.label, 'Application quality · Needs info');
      expect(result.reasons, contains('Needs missing info'));
      expect(result.reasons, contains('Missing Web3, GraphQL'));
    });
  });

  test('evaluates tracked applications using their current phase', () {
    final result = evaluateTrackedApplicationQuality(
      _trackedApplication(phase: ApplicationPhase.sent, trustRiskLevel: 'low'),
    );

    expect(result.score, 100);
    expect(result.label, 'Application quality · Ready');
    expect(result.reasons, contains('Already sent'));
  });
}

PipelineCard _card({
  JobCategory category = JobCategory.ready,
  PipelineStage stage = PipelineStage.matched,
  String trustRiskLevel = 'low',
  List<String> missingSkills = const [],
}) {
  return PipelineCard(
    id: 'card_1',
    status: PipelineCardStatus.pending,
    createdAt: DateTime(2026, 6, 5),
    stage: stage,
    trustRiskLevel: trustRiskLevel,
    trustRiskLabel: _trustLabel(trustRiskLevel),
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
  String trustRiskLevel = 'low',
}) {
  final draftedAt = DateTime(2026, 6, 5, 9);
  final sentAt = switch (phase) {
    ApplicationPhase.draft => null,
    ApplicationPhase.sent ||
    ApplicationPhase.replied => DateTime(2026, 6, 5, 10),
  };

  return TrackedApplication(
    id: 'app_1',
    job: _card(trustRiskLevel: trustRiskLevel).job,
    draftedAt: draftedAt,
    sentAt: sentAt,
    gotReply: phase == ApplicationPhase.replied,
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
