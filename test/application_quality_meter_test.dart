import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/firestore/pipeline_repository.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/data/models/tracked_application.dart';
import 'package:syncra/features/jobs/services/application_quality_meter.dart';

void main() {
  group('Application Quality Meter', () {
    test('marks a drafted strong fit as ready', () {
      final result = evaluateApplicationQuality(
        _card(
          category: JobCategory.ready,
          stage: PipelineStage.drafted,
        ),
      );

      // base 35 + ready 25 + no-missing 15 + drafted 16 = 91
      expect(result.score, 91);
      expect(result.label, 'Application quality · Ready');
      expect(result.reasons, contains('All Match'));
      expect(result.reasons, contains('Draft ready'));
    });

    test('scores a freshly matched strong fit below a drafted one', () {
      final result = evaluateApplicationQuality(
        _card(
          category: JobCategory.ready,
          stage: PipelineStage.matched,
        ),
      );

      // base 35 + ready 25 + no-missing 15 + matched 0 = 75
      expect(result.score, 75);
      expect(result.label, 'Application quality · Needs polish');
    });

    test('explains missing skills for incomplete matches', () {
      final result = evaluateApplicationQuality(
        _card(
          category: JobCategory.inputNeeded,
          stage: PipelineStage.drafted,
          missingSkills: const ['Web3', 'GraphQL'],
        ),
      );

      // base 35 + inputNeeded 14 - missing(2*5=10) + drafted 16 = 55
      expect(result.score, 55);
      expect(result.label, 'Application quality · Needs info');
      expect(result.reasons, contains('Several Match'));
      expect(result.reasons, contains('Missing Web3, GraphQL'));
    });
  });

  test('evaluates tracked applications using their current phase', () {
    final result = evaluateTrackedApplicationQuality(
      _trackedApplication(phase: ApplicationPhase.sent),
    );

    // base 35 + ready 25 + no-missing 15 + sent 18 = 93
    expect(result.score, 93);
    expect(result.label, 'Application quality · Ready');
    expect(result.reasons, contains('Already sent'));
  });
}

PipelineCard _card({
  JobCategory category = JobCategory.ready,
  PipelineStage stage = PipelineStage.matched,
  List<String> missingSkills = const [],
}) {
  return PipelineCard(
    id: 'card_1',
    status: PipelineCardStatus.pending,
    createdAt: DateTime(2026, 6, 5),
    stage: stage,
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
  );
}
