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
    trustRiskLevel: card.trustRiskLevel,
    stage: card.stage,
  );
}

ApplicationQualityResult evaluateTrackedApplicationQuality(
  TrackedApplication app,
) {
  return evaluateApplicationQualityFor(
    job: app.job,
    trustRiskLevel: app.trustRiskLevel,
    stage: _stageFromApplicationPhase(app.phase),
  );
}

ApplicationQualityResult evaluateApplicationQualityFor({
  required Job job,
  required String trustRiskLevel,
  required PipelineStage stage,
}) {
  final rawScore = _rawApplicationQualityScore(
    job: job,
    trustRiskLevel: trustRiskLevel,
    stage: stage,
  );
  final score = _cappedApplicationQualityScore(rawScore, trustRiskLevel);

  return ApplicationQualityResult(
    score: score,
    label: _applicationQualityLabel(score),
    reasons: _applicationQualityReasons(
      job: job,
      trustRiskLevel: trustRiskLevel,
      stage: stage,
    ),
  );
}

int _rawApplicationQualityScore({
  required Job job,
  required String trustRiskLevel,
  required PipelineStage stage,
}) {
  var score = 35;

  score += switch (job.category) {
    JobCategory.ready => 25,
    JobCategory.inputNeeded => 14,
    JobCategory.exploration => 6,
  };

  score += switch (trustRiskLevel) {
    'low' => 20,
    'medium' => -8,
    'high' => -30,
    _ => 8,
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

int _cappedApplicationQualityScore(int rawScore, String trustRiskLevel) {
  final clamped = rawScore.clamp(0, 100).toInt();
  return switch (trustRiskLevel) {
    'high' => clamped.clamp(0, 35).toInt(),
    'medium' => clamped.clamp(0, 59).toInt(),
    'unchecked' => clamped.clamp(0, 74).toInt(),
    _ => clamped,
  };
}

String _applicationQualityLabel(int score) {
  if (score >= 80) return 'Application quality · Ready';
  if (score >= 60) return 'Application quality · Needs polish';
  if (score >= 40) return 'Application quality · Needs info';
  return 'Application quality · Blocked';
}

List<String> _applicationQualityReasons({
  required Job job,
  required String trustRiskLevel,
  required PipelineStage stage,
}) {
  final reasons = <String>[];

  reasons.add(switch (trustRiskLevel) {
    'high' => 'Trust blocked',
    'medium' => 'Verify trust first',
    'low' => 'Trust looks okay',
    _ => 'Trust not checked',
  });

  reasons.add(switch (job.category) {
    JobCategory.ready => 'Resume fit strong',
    JobCategory.inputNeeded => 'Needs missing info',
    JobCategory.exploration => 'Stretch role',
  });

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
