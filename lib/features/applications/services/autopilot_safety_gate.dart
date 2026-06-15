import '../../../data/models/tracked_application.dart';
import '../../auth/models/user_profile.dart';
import '../../email/models/recipient_resolution.dart';
import '../../jobs/services/job_trust_guard.dart';
import 'auto_apply_eligibility.dart';

class AutopilotSafetyDecision {
  const AutopilotSafetyDecision({required this.allowed, required this.reasons});

  final bool allowed;
  final List<String> reasons;
}

AutopilotSafetyDecision evaluateAutopilotSendSafety({
  required AutonomyLevel autonomyLevel,
  required AutoApplySettings settings,
  required TrackedApplication application,
  required int sentToday,
  required RecipientResolution recipient,
}) {
  final reasons = <String>[];
  final usedToday = sentToday < 0 ? 0 : sentToday;

  if (autonomyLevel != AutonomyLevel.autopilot) {
    reasons.add('Autopilot is not enabled');
  }

  if (!settings.enabled) {
    reasons.add('Auto-apply is off');
  }

  if (!settings.autoSendOutreach) {
    reasons.add('Auto-send outreach is off');
  }

  if (application.phase != ApplicationPhase.draft) {
    reasons.add(
      application.phase == ApplicationPhase.sent
          ? 'Application is already sent'
          : 'Application is already ${application.phase.label.toLowerCase()}',
    );
  }

  if (usedToday >= settings.maxDailyApplications) {
    reasons.add('Daily limit reached');
  }

  if (settings.requireLowTrust && application.trustRiskLevel != 'low') {
    reasons.add('Trust is not low-risk');
  }

  final eligibility = evaluateAutoApplyEligibility(
    app: application,
    settings: settings,
    sentToday: usedToday,
  );
  if (eligibility.bundle.hasBlocker) {
    reasons.add('Application bundle needs review');
  }
  if (eligibility.qualityScore < settings.minQualityScore) {
    reasons.add(
      'Quality ${eligibility.qualityScore}% is below '
      '${settings.minQualityScore}% minimum',
    );
  }

  final trust = JobTrustGuardResult(
    riskLevel: application.trustRiskLevel,
    riskLabel: application.trustRiskLabel,
    signals: application.trustSignals,
    safeNextStep: application.trustSafeNextStep,
  );
  final outreachAllowed = shouldAutoSendOutreach(
    settings: settings,
    trust: trust,
    recipient: recipient,
  );
  if (!recipient.hasEmail ||
      recipient.requiresUserConfirmation ||
      !recipient.isAutoSendEligible) {
    reasons.add('Recipient is not confirmed');
  }

  if (!outreachAllowed && reasons.isEmpty) {
    reasons.add('Autopilot safety gate failed');
  }

  return AutopilotSafetyDecision(
    allowed: reasons.isEmpty,
    reasons: List.unmodifiable(reasons),
  );
}
