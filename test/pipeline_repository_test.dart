import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/firestore/pipeline_repository.dart';
import 'package:syncra/data/models/job.dart';

void main() {
  group('active pipeline filtering', () {
    test('keeps unfinished pending cards visible', () {
      for (final stage in const [
        PipelineStage.matched,
        PipelineStage.tailored,
        PipelineStage.drafted,
      ]) {
        expect(
          shouldShowInActivePipeline(_card(stage: stage)),
          isTrue,
          reason: '${stage.name} should remain in the active pipeline.',
        );
      }
    });

    test('hides pending cards once they are sent or replied', () {
      expect(
        shouldShowInActivePipeline(_card(stage: PipelineStage.sent)),
        isFalse,
      );
      expect(
        shouldShowInActivePipeline(_card(stage: PipelineStage.replied)),
        isFalse,
      );
    });

    test('hides non-pending cards even when they are unfinished', () {
      expect(
        shouldShowInActivePipeline(_card(status: PipelineCardStatus.approved)),
        isFalse,
      );
      expect(
        shouldShowInActivePipeline(_card(status: PipelineCardStatus.dismissed)),
        isFalse,
      );
    });
  });

  group('pipeline stage patching', () {
    test('advances unfinished stages without approving the card', () {
      expect(
        pipelineStagePatchFor(
          current: PipelineStage.matched,
          target: PipelineStage.tailored,
        ),
        {'stage': 'tailored'},
      );

      expect(
        pipelineStagePatchFor(
          current: PipelineStage.tailored,
          target: PipelineStage.drafted,
        ),
        {'stage': 'drafted'},
      );
    });

    test('does not rewind or rewrite a card for older unfinished stages', () {
      expect(
        pipelineStagePatchFor(
          current: PipelineStage.drafted,
          target: PipelineStage.tailored,
        ),
        isEmpty,
      );

      expect(
        pipelineStagePatchFor(
          current: PipelineStage.drafted,
          target: PipelineStage.drafted,
        ),
        isEmpty,
      );
    });

    test('marks sent cards approved so they leave the active pipeline', () {
      expect(
        pipelineStagePatchFor(
          current: PipelineStage.drafted,
          target: PipelineStage.sent,
        ),
        {'stage': 'sent', 'status': 'approved'},
      );
    });

    test('marks replied cards approved so they leave the active pipeline', () {
      expect(
        pipelineStagePatchFor(
          current: PipelineStage.sent,
          target: PipelineStage.replied,
        ),
        {'stage': 'replied', 'status': 'approved'},
      );
    });

    test(
      'approves already-terminal cards even when no stage advance is needed',
      () {
        expect(
          pipelineStagePatchFor(
            current: PipelineStage.sent,
            target: PipelineStage.sent,
          ),
          {'status': 'approved'},
        );

        expect(
          pipelineStagePatchFor(
            current: PipelineStage.replied,
            target: PipelineStage.replied,
          ),
          {'status': 'approved'},
        );
      },
    );
  });
}

PipelineCard _card({
  PipelineCardStatus status = PipelineCardStatus.pending,
  PipelineStage stage = PipelineStage.matched,
}) {
  return PipelineCard(
    id: 'card_${status.name}_${stage.name}',
    status: status,
    stage: stage,
    createdAt: DateTime(2026, 6, 6),
    job: _job(),
  );
}

Job _job() {
  return const Job(
    id: 'job_pipeline_test',
    title: 'Frontend Engineer',
    company: 'Syncra Test Co',
    location: 'Remote',
    salary: '',
    category: JobCategory.ready,
    matchScore: 0,
    agentAction: '',
    agentJustification: '',
    skills: [],
    missingSkills: [],
    why: 'Build polished Flutter interfaces.',
  );
}
