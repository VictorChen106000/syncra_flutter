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

  group('pipeline card dedupe', () {
    test('keeps one active card per job id', () {
      final cards = [
        _card(id: 'older', jobId: 'job_a', createdAt: DateTime(2026, 6, 6, 9)),
        _card(id: 'newer', jobId: 'job_a', createdAt: DateTime(2026, 6, 6, 10)),
        _card(id: 'other', jobId: 'job_b', createdAt: DateTime(2026, 6, 6, 11)),
      ];

      final deduped = dedupePipelineCardsByJobId(cards);

      expect(deduped.map((card) => card.job.id), ['job_b', 'job_a']);
      expect(deduped.where((card) => card.job.id == 'job_a'), hasLength(1));
    });

    test('keeps the highest stage for duplicate job ids', () {
      final best = pickBestPipelineCardForJob([
        _card(
          id: 'newer_matched',
          jobId: 'job_a',
          stage: PipelineStage.matched,
          createdAt: DateTime(2026, 6, 6, 12),
        ),
        _card(
          id: 'older_drafted',
          jobId: 'job_a',
          stage: PipelineStage.drafted,
          createdAt: DateTime(2026, 6, 6, 9),
        ),
      ]);

      expect(best.id, 'older_drafted');
    });

    test('keeps the newest card when duplicate stages tie', () {
      final best = pickBestPipelineCardForJob([
        _card(
          id: 'older',
          jobId: 'job_a',
          stage: PipelineStage.tailored,
          createdAt: DateTime(2026, 6, 6, 9),
        ),
        _card(
          id: 'newer',
          jobId: 'job_a',
          stage: PipelineStage.tailored,
          createdAt: DateTime(2026, 6, 6, 10),
        ),
      ]);

      expect(best.id, 'newer');
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
  String? id,
  String jobId = 'job_pipeline_test',
  PipelineCardStatus status = PipelineCardStatus.pending,
  PipelineStage stage = PipelineStage.matched,
  DateTime? createdAt,
}) {
  return PipelineCard(
    id: id ?? 'card_${status.name}_${stage.name}',
    status: status,
    stage: stage,
    createdAt: createdAt ?? DateTime(2026, 6, 6),
    job: _job(id: jobId),
  );
}

Job _job({required String id}) {
  return Job(
    id: id,
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
