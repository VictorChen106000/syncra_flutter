import '../../../data/firestore/pipeline_repository.dart';
import '../../../data/models/job.dart';

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
  var score = _rawApplicationQualityScore(card);

  // Trust gates the meter. A high-risk job should never look "ready",
  // and unchecked legacy cards should not look fully ready either.
  score = switch (card.trustRiskLevel) {
    'high' => score.clamp(0, 35).toInt(),
    'medium' => score.clamp(0, 59).toInt(),
    'unchecked' => score.clamp(0, 74).toInt(),
    _ => score.clamp(0, 100).toInt(),
  };

  return ApplicationQualityResult(
    score: score,
    label: _applicationQualityLabel(score),
    reasons: _applicationQualityReasons(card),
  );
}

int _rawApplicationQualityScore(PipelineCard card) {
  var score = 35;

  score += switch (card.job.category) {
    JobCategory.ready => 25,
    JobCategory.inputNeeded => 14,
    JobCategory.exploration => 6,
  };

  score += switch (card.trustRiskLevel) {
    'low' => 20,
    'unchecked' => 8,
    'medium' => -8,
    'high' => -30,
    _ => 0,
  };

  if (card.job.missingSkills.isEmpty) {
    score += 15;
  } else {
    score -= (card.job.missingSkills.length * 5).clamp(0, 15).toInt();
  }

  score += switch (card.stage) {
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

List<String> _applicationQualityReasons(PipelineCard card) {
  final reasons = <String>[];

  if (card.trustRiskLevel == 'high') {
    reasons.add('Trust blocked');
  } else if (card.trustRiskLevel == 'medium') {
    reasons.add('Verify trust first');
  } else if (card.trustRiskLevel == 'low') {
    reasons.add('Trust looks okay');
  } else {
    reasons.add('Trust not checked');
  }

  switch (card.job.category) {
    case JobCategory.ready:
      reasons.add('Resume fit strong');
    case JobCategory.inputNeeded:
      reasons.add('Needs missing info');
    case JobCategory.exploration:
      reasons.add('Stretch role');
  }

  if (card.job.missingSkills.isNotEmpty) {
    reasons.add('Missing ${card.job.missingSkills.take(2).join(', ')}');
  }

  switch (card.stage) {
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
