import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/email/models/recipient_resolution.dart';
import 'package:syncra/features/email/services/recipient_confidence_gate.dart';

void main() {
  group('evaluateRecipientGate', () {
    test('allows auto-send for confirmed recipients that can auto-send', () {
      final decision = evaluateRecipientGate(
        RecipientResolution.confirmed(
          email: 'careers@example.com',
          domain: 'example.com',
        ),
      );

      expect(decision.action, RecipientGateAction.autoSendAllowed);
      expect(decision.canAutoSend, isTrue);
    });

    test('allows auto-send for high-confidence official recipients', () {
      final decision = evaluateRecipientGate(
        _resolution(
          confidence: RecipientConfidence.high,
          source: RecipientSource.officialCompanyWebsite,
          canAutoSend: true,
          requiresUserConfirmation: false,
        ),
      );

      expect(decision.action, RecipientGateAction.autoSendAllowed);
      expect(decision.canAutoSend, isTrue);
    });

    test('stops at draft for medium-confidence recipients', () {
      final decision = evaluateRecipientGate(
        _resolution(
          confidence: RecipientConfidence.medium,
          source: RecipientSource.officialCompanyWebsite,
          canAutoSend: false,
          requiresUserConfirmation: true,
        ),
      );

      expect(decision.action, RecipientGateAction.stopAtDraft);
      expect(decision.stopsAtDraft, isTrue);
    });

    test('stops at draft for low-confidence guessed recipients', () {
      final decision = evaluateRecipientGate(
        RecipientResolution.guessed(
          email: 'careers@example.com',
          domain: 'example.com',
        ),
      );

      expect(decision.action, RecipientGateAction.stopAtDraft);
      expect(decision.canAutoSend, isFalse);
    });

    test('stops at draft when no recipient email exists', () {
      final decision = evaluateRecipientGate(
        RecipientResolution.none(domain: 'example.com'),
      );

      expect(decision.action, RecipientGateAction.stopAtDraft);
      expect(decision.canAutoSend, isFalse);
    });

    test('stops at draft when high-confidence recipient cannot auto-send', () {
      final decision = evaluateRecipientGate(
        _resolution(
          confidence: RecipientConfidence.high,
          source: RecipientSource.officialCompanyWebsite,
          canAutoSend: false,
          requiresUserConfirmation: false,
        ),
      );

      expect(decision.action, RecipientGateAction.stopAtDraft);
      expect(decision.canAutoSend, isFalse);
    });
  });
}

RecipientResolution _resolution({
  required RecipientConfidence confidence,
  required RecipientSource source,
  required bool canAutoSend,
  required bool requiresUserConfirmation,
}) {
  return RecipientResolution(
    email: 'careers@example.com',
    domain: 'example.com',
    confidence: confidence,
    source: source,
    label: RecipientResolution.labelFor(source: source, confidence: confidence),
    reason: RecipientResolution.reasonFor(
      source: source,
      confidence: confidence,
    ),
    canAutoSend: canAutoSend,
    requiresUserConfirmation: requiresUserConfirmation,
  );
}
