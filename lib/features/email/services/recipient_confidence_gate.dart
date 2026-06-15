import '../models/recipient_resolution.dart';

enum RecipientGateAction { autoSendAllowed, stopAtDraft }

class RecipientGateDecision {
  const RecipientGateDecision({required this.action, required this.reason});

  final RecipientGateAction action;
  final String reason;

  bool get canAutoSend => action == RecipientGateAction.autoSendAllowed;
  bool get stopsAtDraft => action == RecipientGateAction.stopAtDraft;
}

RecipientGateDecision evaluateRecipientGate(RecipientResolution resolution) {
  final email = resolution.email.trim();

  if (email.isEmpty) {
    return const RecipientGateDecision(
      action: RecipientGateAction.stopAtDraft,
      reason: 'No usable recipient email was found.',
    );
  }

  final verified =
      resolution.confidence == RecipientConfidence.confirmed ||
      resolution.confidence == RecipientConfidence.high;

  if (verified && resolution.canAutoSend) {
    return RecipientGateDecision(
      action: RecipientGateAction.autoSendAllowed,
      reason: resolution.confidence == RecipientConfidence.confirmed
          ? 'Recipient is confirmed from the company contact cache.'
          : 'Recipient is high-confidence from an official company source.',
    );
  }

  return const RecipientGateDecision(
    action: RecipientGateAction.stopAtDraft,
    reason: 'Recipient is not verified enough for automatic sending.',
  );
}
