import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/applications/services/auto_apply_eligibility.dart';
import 'package:syncra/features/auth/models/user_profile.dart';
import 'package:syncra/features/jobs/services/job_trust_guard.dart';

JobTrustGuardResult _trust(String level) => JobTrustGuardResult(
  riskLevel: level,
  riskLabel: level,
  signals: const [],
  safeNextStep: '',
);

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
    test('false when the setting is off, even for a low-risk job', () {
      expect(
        shouldAutoSendOutreach(
          settings: const AutoApplySettings(autoSendOutreach: false),
          trust: _trust('low'),
        ),
        isFalse,
      );
    });

    test('true when on and the job is low risk', () {
      expect(
        shouldAutoSendOutreach(
          settings: const AutoApplySettings(autoSendOutreach: true),
          trust: _trust('low'),
        ),
        isTrue,
      );
    });

    test('false when on but the job is medium or high risk', () {
      for (final level in ['medium', 'high']) {
        expect(
          shouldAutoSendOutreach(
            settings: const AutoApplySettings(autoSendOutreach: true),
            trust: _trust(level),
          ),
          isFalse,
          reason: '$level risk must fall back to manual review',
        );
      }
    });
  });
}
