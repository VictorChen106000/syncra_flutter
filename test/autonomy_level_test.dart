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
      'fromStorage defaults to Auto-draft for null / unknown / wrong type',
      () {
        expect(AutonomyLevel.fromStorage(null), AutonomyLevel.autoDraft);
        expect(AutonomyLevel.fromStorage(''), AutonomyLevel.autoDraft);
        expect(AutonomyLevel.fromStorage('nonsense'), AutonomyLevel.autoDraft);
        expect(AutonomyLevel.fromStorage(42), AutonomyLevel.autoDraft);
      },
    );

    test('exposes a human label for each level', () {
      expect(AutonomyLevel.assist.label, 'Assist');
      expect(AutonomyLevel.autoDraft.label, 'Auto-draft');
      expect(AutonomyLevel.autopilot.label, 'Autopilot');
    });
  });

  group('UserProfile autonomy persistence', () {
    test('defaults to Auto-draft when the field is absent (legacy users)', () {
      final profile = UserProfile.fromMap({'name': 'Ada', 'email': 'a@b.co'});
      expect(profile.autonomyLevel, AutonomyLevel.autoDraft);
      expect(profile.autoApplySettings.maxDailyApplications, 0);
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

    test('default constructor is Auto-draft', () {
      const profile = UserProfile(name: 'Ada', email: 'a@b.co');
      expect(profile.autonomyLevel, AutonomyLevel.autoDraft);
      expect(profile.autoApplySettings.maxDailyApplications, 0);
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
  // re-derives fixed hidden safety policy. Only Autopilot may enable
  // auto-apply / auto-send — Assist and Auto-draft always disable both.
  group('AutonomyLevel.applyToAutoApply', () {
    test('Assist maps to the fixed manual safety policy', () {
      const current = AutoApplySettings(
        enabled: true,
        autoSendOutreach: true,
        minQualityScore: 90,
        maxDailyApplications: 5,
        requireLowTrust: false,
      );
      final mapped = AutonomyLevel.assist.applyToAutoApply(current);
      expect(mapped.enabled, isFalse);
      expect(mapped.autoSendOutreach, isFalse);
      expect(mapped.minQualityScore, 100);
      expect(mapped.maxDailyApplications, 0);
      expect(mapped.requireLowTrust, isTrue);
    });

    test('Auto-draft maps to the fixed draft-only safety policy', () {
      const current = AutoApplySettings(
        enabled: true,
        autoSendOutreach: true,
        minQualityScore: 80,
        maxDailyApplications: 2,
      );
      final mapped = AutonomyLevel.autoDraft.applyToAutoApply(current);
      expect(mapped.enabled, isFalse);
      expect(mapped.autoSendOutreach, isFalse);
      expect(mapped.minQualityScore, 85);
      expect(mapped.maxDailyApplications, 0);
      expect(mapped.requireLowTrust, isTrue);
    });

    test('Autopilot enables auto-apply, auto-send, and the low-trust gate', () {
      final mapped = AutonomyLevel.autopilot.applyToAutoApply(
        const AutoApplySettings(),
      );
      expect(mapped.enabled, isTrue);
      expect(mapped.autoSendOutreach, isTrue);
      expect(mapped.requireLowTrust, isTrue);
    });

    test('Autopilot defaults safety values to 85% / 3 a day / low-risk', () {
      final mapped = AutonomyLevel.autopilot.applyToAutoApply(
        const AutoApplySettings(),
      );
      expect(mapped.minQualityScore, 85);
      expect(mapped.maxDailyApplications, 3);
      expect(mapped.requireLowTrust, isTrue);
    });

    test('Autopilot ignores stale custom quality / daily-limit values', () {
      const current = AutoApplySettings(
        minQualityScore: 95,
        maxDailyApplications: 10,
      );
      final mapped = AutonomyLevel.autopilot.applyToAutoApply(current);
      expect(mapped.minQualityScore, 85);
      expect(mapped.maxDailyApplications, 3);
      expect(mapped.enabled, isTrue);
      expect(mapped.autoSendOutreach, isTrue);
    });

    test('fixedAutoApplySettingsFor matches applyToAutoApply', () {
      for (final level in AutonomyLevel.values) {
        expect(
          fixedAutoApplySettingsFor(level).toMap(),
          level.applyToAutoApply(const AutoApplySettings()).toMap(),
        );
      }
    });
  });
}
