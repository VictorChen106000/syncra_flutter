import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/applications/services/auto_apply_eligibility.dart';
import 'package:syncra/features/auth/models/user_profile.dart';
import 'package:syncra/features/email/models/recipient_resolution.dart';

void main() {
  group('AutoApplySettings.autoSendOutreach', () {
    test('defaults to false', () {
      expect(const AutoApplySettings().autoSendOutreach, isFalse);
    });

    test('round-trips true through toMap/fromMap', () {
      const settings = AutoApplySettings(autoSendOutreach: true);
      final restored = AutoApplySettings.fromMap(settings.toMap());
      expect(restored.autoSendOutreach, isTrue);
    });

    test('fromMap defaults the flag to false when absent', () {
      final restored = AutoApplySettings.fromMap({'enabled': true});
      expect(restored.autoSendOutreach, isFalse);
    });
  });

  group('shouldAutoSendOutreach', () {
    test('false when the setting is off, even for a confirmed recipient', () {
      expect(
        shouldAutoSendOutreach(
          settings: const AutoApplySettings(autoSendOutreach: false),
          recipient: _confirmedRecipient(),
        ),
        isFalse,
      );
    });

    test('true when bounded auto-apply, auto-send, and recipient pass', () {
      expect(
        shouldAutoSendOutreach(
          settings: const AutoApplySettings(
            enabled: true,
            autoSendOutreach: true,
          ),
          recipient: _confirmedRecipient(),
        ),
        isTrue,
      );
    });

    test('false for guessed recipients even when other gates pass', () {
      expect(
        shouldAutoSendOutreach(
          settings: const AutoApplySettings(
            enabled: true,
            autoSendOutreach: true,
          ),
          recipient: RecipientResolution.guessed(
            email: 'careers@example.com',
            domain: 'example.com',
          ),
        ),
        isFalse,
      );
    });
  });
}

RecipientResolution _confirmedRecipient() => RecipientResolution.confirmed(
  email: 'talent@example.com',
  domain: 'example.com',
);
