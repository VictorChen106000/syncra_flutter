import '../../../data/firestore/pipeline_repository.dart';
import '../../../data/models/job.dart';
import '../../../data/models/tracked_application.dart';

class ApplicationQualityResult {
  const ApplicationQualityResult({
    required this.score,
    required this.label,
    required this.reasons,
  });

  final int score;
  final String label;
  final List<String> reasons;
}

ApplicationQualityResult evaluateApplicationQuality(PipelineCard card) {
  return evaluateApplicationQualityFor(
    job: card.job,
    stage: card.stage,
  );
}

ApplicationQualityResult evaluateTrackedApplicationQuality(
  TrackedApplication app,
) {
  return evaluateApplicationQualityFor(
    job: app.job,
    stage: _stageFromApplicationPhase(app.phase),
  );
}

ApplicationQualityResult evaluateApplicationQualityFor({
  required Job job,
  required PipelineStage stage,
}) {
  final score = _rawApplicationQualityScore(
    job: job,
    stage: stage,
  ).clamp(0, 100).toInt();

  return ApplicationQualityResult(
    score: score,
    label: _applicationQualityLabel(score),
    reasons: _applicationQualityReasons(
      job: job,
      stage: stage,
    ),
  );
}

int _rawApplicationQualityScore({
  required Job job,
  required PipelineStage stage,
}) {
  var score = 35;

  score += switch (job.category) {
    JobCategory.ready => 25,
    JobCategory.inputNeeded => 14,
    JobCategory.exploration => 6,
  };

  if (job.missingSkills.isEmpty) {
    score += 15;
  } else {
    score -= (job.missingSkills.length * 5).clamp(0, 15).toInt();
  }

  score += switch (stage) {
    PipelineStage.replied || PipelineStage.sent => 18,
    PipelineStage.drafted => 16,
    PipelineStage.tailored => 10,
    PipelineStage.matched => 0,
  };

  return score;
}

String _applicationQualityLabel(int score) {
  if (score >= 80) return 'Application quality · Ready';
  if (score >= 60) return 'Application quality · Needs polish';
  if (score >= 40) return 'Application quality · Needs info';
  return 'Application quality · Blocked';
}

List<String> _applicationQualityReasons({
  required Job job,
  required PipelineStage stage,
}) {
  final reasons = <String>[];

  // Use the single canonical match label so the meter never invents its own
  // wording ("Stretch role", "Resume fit strong") that drifts from the three
  // labels shown everywhere else: All Match / Several Match / No Match.
  reasons.add(job.matchLabel);

  if (job.missingSkills.isNotEmpty) {
    reasons.add('Missing ${job.missingSkills.take(2).join(', ')}');
  }

  switch (stage) {
    case PipelineStage.drafted:
      reasons.add('Draft ready');
    case PipelineStage.tailored:
      reasons.add('Resume tailored');
    case PipelineStage.sent:
      reasons.add('Already sent');
    case PipelineStage.replied:
      reasons.add('Reply received');
    case PipelineStage.matched:
      break;
  }

  return reasons;
}

PipelineStage _stageFromApplicationPhase(ApplicationPhase phase) {
  return switch (phase) {
    ApplicationPhase.draft => PipelineStage.drafted,
    ApplicationPhase.sent => PipelineStage.sent,
    ApplicationPhase.replied => PipelineStage.replied,
  };
}
