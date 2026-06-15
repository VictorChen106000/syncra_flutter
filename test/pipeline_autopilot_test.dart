import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/firestore/pipeline_repository.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/features/agent/state/pipeline_autopilot_notifier.dart';
import 'package:syncra/features/auth/models/user_profile.dart';

/// Guards the pipeline auto-processor's pure gating: WHICH cards it may touch
/// and HOW FAR it carries them per autonomy level. The Firestore/LLM side is
/// integration-tested by hand; this locks the safety boundaries.
void main() {
  group('pipelineAutopilotStopStage', () {
    test('Assist does nothing', () {
      expect(pipelineAutopilotStopStage(AutonomyLevel.assist), isNull);
    });

    test('Auto-draft stops at Drafted (never sends)', () {
      expect(
        pipelineAutopilotStopStage(AutonomyLevel.autoDraft),
        PipelineStage.drafted,
      );
    });

    test('Autopilot carries through to Sent', () {
      expect(
        pipelineAutopilotStopStage(AutonomyLevel.autopilot),
        PipelineStage.sent,
      );
    });
  });

  group('pipelineAutopilotCandidates', () {
    test('accepts strong and partial matched cards', () {
      expect(
        pipelineAutopilotCandidates([_card(category: JobCategory.ready)]),
        hasLength(1),
      );
      expect(
        pipelineAutopilotCandidates([_card(category: JobCategory.inputNeeded)]),
        hasLength(1),
      );
    });

    test('skips stretch (exploration) matches', () {
      expect(
        pipelineAutopilotCandidates([_card(category: JobCategory.exploration)]),
        isEmpty,
      );
    });

    test('skips anything past the matched stage', () {
      for (final stage in [
        PipelineStage.tailored,
        PipelineStage.drafted,
        PipelineStage.sent,
        PipelineStage.replied,
      ]) {
        expect(
          pipelineAutopilotCandidates([_card(stage: stage)]),
          isEmpty,
          reason: 'stage $stage must not be reprocessed',
        );
      }
    });

    test('selects matched cards before send-time safety gates run', () {
      for (final risk in ['low', 'medium', 'high', 'unchecked']) {
        expect(
          pipelineAutopilotCandidates([_card(trustRiskLevel: risk)]),
          hasLength(1),
          reason: 'risk $risk can still draft; send safety gates it later',
        );
      }
    });

    test('skips approved / dismissed cards', () {
      expect(
        pipelineAutopilotCandidates([
          _card(status: PipelineCardStatus.approved),
          _card(status: PipelineCardStatus.dismissed),
        ]),
        isEmpty,
      );
    });
  });
}

PipelineCard _card({
  JobCategory category = JobCategory.ready,
  PipelineStage stage = PipelineStage.matched,
  PipelineCardStatus status = PipelineCardStatus.pending,
  String trustRiskLevel = 'low',
}) {
  return PipelineCard(
    id: 'card_${category.name}_${stage.name}_${status.name}_$trustRiskLevel',
    status: status,
    stage: stage,
    createdAt: DateTime(2026, 6, 15),
    trustRiskLevel: trustRiskLevel,
    job: Job(
      id: 'job_$trustRiskLevel',
      title: 'Frontend Engineer',
      company: 'Syncra Test Co',
      location: 'Remote',
      salary: '',
      category: category,
      matchScore: 0,
      agentAction: '',
      agentJustification: '',
      skills: const [],
      missingSkills: const [],
      why: '',
    ),
  );
}
