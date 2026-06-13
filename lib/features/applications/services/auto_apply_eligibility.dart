import '../../../data/models/tracked_application.dart';
import '../../auth/models/user_profile.dart';
import '../../jobs/services/job_trust_guard.dart';
import 'application_bundle_summary.dart';

/// Whether the agent may auto-send a drafted outreach email instead of stopping
/// at the manual review sheet.
///
/// The trust floor is deliberate: auto-send puts the user's real email address
/// and resume in front of an employer with no human glance, so it only fires for
/// `low`-risk jobs. Medium/high-risk postings (see [evaluateJobTrust]) always
/// fall back to manual review even when the setting is on.
bool shouldAutoSendOutreach({
  required AutoApplySettings settings,
  required JobTrustGuardResult trust,
}) {
  return settings.autoSendOutreach && trust.riskLevel == 'low';
}

class AutoApplyEligibilityResult {
  const AutoApplyEligibilityResult({
    required this.isEligible,
    required this.statusLabel,
    required this.reasons,
    required this.bundle,
  });

  final bool isEligible;
  final String statusLabel;
  final List<String> reasons;
  final ApplicationBundleSummary bundle;

  int get qualityScore => bundle.quality.score;
}

AutoApplyEligibilityResult evaluateAutoApplyEligibility({
  required TrackedApplication app,
  required AutoApplySettings settings,
  required int sentToday,
}) {
  final bundle = evaluateApplicationBundle(app);
  final reasons = <String>[];
  final usedToday = sentToday < 0 ? 0 : sentToday;

  if (!settings.enabled) {
    reasons.add('Auto-apply is off');
  }

  if (app.phase != ApplicationPhase.draft) {
    reasons.add('Application is already ${app.phase.label.toLowerCase()}');
  }

  if (usedToday >= settings.maxDailyApplications) {
    reasons.add('Daily limit reached');
  }

  if (settings.requireLowTrust && app.trustRiskLevel != 'low') {
    reasons.add('Trust must be low risk');
  }

  if (bundle.hasBlocker) {
    reasons.add('Bundle needs review');
    reasons.addAll(
      bundle.items
          .where((item) => item.isBlocking)
          .map((item) => '${item.label}: ${item.detail}')
          .take(2),
    );
  }

  if (bundle.quality.score < settings.minQualityScore) {
    reasons.add(
      'Quality ${bundle.quality.score}% is below '
      '${settings.minQualityScore}% minimum',
    );
  }

  final isEligible = reasons.isEmpty;

  return AutoApplyEligibilityResult(
    isEligible: isEligible,
    statusLabel: isEligible ? 'Ready for bounded auto-apply' : reasons.first,
    reasons: List.unmodifiable(reasons),
    bundle: bundle,
  );
}
