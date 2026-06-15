import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/auth/models/user_profile.dart';

/// Guards the autonomy dial's persistence contract: the enum must round-trip
/// through its stored key, and legacy / malformed profiles must default to
/// Auto-draft (never silently land a user in Autopilot).
void main() {
  group('AutonomyLevel storage', () {
    test('storageKey is stable for every level', () {
      expect(AutonomyLevel.assist.storageKey, 'assist');
      expect(AutonomyLevel.autoDraft.storageKey, 'auto_draft');
      expect(AutonomyLevel.autopilot.storageKey, 'autopilot');
    });

    test('fromStorage round-trips each storageKey', () {
      for (final level in AutonomyLevel.values) {
        expect(AutonomyLevel.fromStorage(level.storageKey), level);
      }
    });

    test(
      'fromStorage defaults to Autopilot for null / unknown / wrong type',
      () {
        expect(AutonomyLevel.fromStorage(null), AutonomyLevel.autopilot);
        expect(AutonomyLevel.fromStorage(''), AutonomyLevel.autopilot);
        expect(AutonomyLevel.fromStorage('nonsense'), AutonomyLevel.autopilot);
        expect(AutonomyLevel.fromStorage(42), AutonomyLevel.autopilot);
      },
    );

    test('exposes a human label for each level', () {
      expect(AutonomyLevel.assist.label, 'Assist');
      expect(AutonomyLevel.autoDraft.label, 'Auto-draft');
      expect(AutonomyLevel.autopilot.label, 'Autopilot');
    });
  });

  group('UserProfile autonomy persistence', () {
    test('defaults to Autopilot when the field is absent (legacy users)', () {
      final profile = UserProfile.fromMap({'name': 'Ada', 'email': 'a@b.co'});
      expect(profile.autonomyLevel, AutonomyLevel.autopilot);
    });

    test('parses each stored autonomy_level value', () {
      for (final level in AutonomyLevel.values) {
        final profile = UserProfile.fromMap({
          'name': 'Ada',
          'email': 'a@b.co',
          'autonomy_level': level.storageKey,
        });
        expect(profile.autonomyLevel, level);
      }
    });

    test('default constructor is Autopilot', () {
      const profile = UserProfile(name: 'Ada', email: 'a@b.co');
      expect(profile.autonomyLevel, AutonomyLevel.autopilot);
    });

    test('copyWith updates the autonomy level and leaves it otherwise', () {
      const base = UserProfile(name: 'Ada', email: 'a@b.co');
      final piloted = base.copyWith(autonomyLevel: AutonomyLevel.autopilot);
      expect(piloted.autonomyLevel, AutonomyLevel.autopilot);
      // Unrelated copyWith must not reset the level back to the default.
      final renamed = piloted.copyWith(name: 'Grace');
      expect(renamed.autonomyLevel, AutonomyLevel.autopilot);
    });
  });

  // Agent Autonomy is the single user-facing control; selecting a level
  // re-derives the internal bounded auto-apply guardrails. Only Autopilot may
  // enable auto-apply / auto-send — Assist and Auto-draft always disable both.
  group('AutonomyLevel.applyToAutoApply', () {
    test('Assist disables auto-apply and auto-send, keeps existing limits', () {
      const current = AutoApplySettings(
        enabled: true,
        autoSendOutreach: true,
        minQualityScore: 90,
        maxDailyApplications: 5,
      );
      final mapped = AutonomyLevel.assist.applyToAutoApply(current);
      expect(mapped.enabled, isFalse);
      expect(mapped.autoSendOutreach, isFalse);
      // Quality / daily values are left untouched.
      expect(mapped.minQualityScore, 90);
      expect(mapped.maxDailyApplications, 5);
    });

    test('Auto-draft disables auto-apply and auto-send, keeps limits', () {
      const current = AutoApplySettings(
        enabled: true,
        autoSendOutreach: true,
        minQualityScore: 80,
        maxDailyApplications: 2,
      );
      final mapped = AutonomyLevel.autoDraft.applyToAutoApply(current);
      expect(mapped.enabled, isFalse);
      expect(mapped.autoSendOutreach, isFalse);
      expect(mapped.minQualityScore, 80);
      expect(mapped.maxDailyApplications, 2);
    });

    test('Autopilot enables auto-apply and auto-send', () {
      final mapped = AutonomyLevel.autopilot.applyToAutoApply(
        const AutoApplySettings(),
      );
      expect(mapped.enabled, isTrue);
      expect(mapped.autoSendOutreach, isTrue);
    });

    test('Autopilot defaults safety values to 85% / 3 a day', () {
      final mapped = AutonomyLevel.autopilot.applyToAutoApply(
        const AutoApplySettings(),
      );
      expect(mapped.minQualityScore, 85);
      expect(mapped.maxDailyApplications, 3);
    });

    test('Autopilot preserves a user\'s custom quality / daily-limit', () {
      const current = AutoApplySettings(
        minQualityScore: 95,
        maxDailyApplications: 10,
      );
      final mapped = AutonomyLevel.autopilot.applyToAutoApply(current);
      expect(mapped.minQualityScore, 95);
      expect(mapped.maxDailyApplications, 10);
      expect(mapped.enabled, isTrue);
      expect(mapped.autoSendOutreach, isTrue);
    });
  });
}
