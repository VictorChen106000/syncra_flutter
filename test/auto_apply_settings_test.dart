import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/auth/models/user_profile.dart';

void main() {
  group('AutoApplySettings', () {
    test('defaults to disabled conservative settings', () {
      const settings = AutoApplySettings();

      expect(settings.enabled, isFalse);
      expect(settings.minQualityScore, 85);
      expect(settings.maxDailyApplications, 3);
      expect(settings.requireLowTrust, isTrue);
      expect(settings.toMap(), {
        'enabled': false,
        'min_quality_score': 85,
        'max_daily_applications': 3,
        'require_low_trust': true,
      });
    });

    test('parses persisted profile settings', () {
      final profile = UserProfile.fromMap({
        'name': 'Jane Doe',
        'email': 'jane@example.com',
        'auto_apply': {
          'enabled': true,
          'min_quality_score': 90,
          'max_daily_applications': 2,
          'require_low_trust': true,
        },
      });

      expect(profile.autoApplySettings.enabled, isTrue);
      expect(profile.autoApplySettings.minQualityScore, 90);
      expect(profile.autoApplySettings.maxDailyApplications, 2);
      expect(profile.autoApplySettings.requireLowTrust, isTrue);
    });

    test('clamps unsafe numeric settings', () {
      final settings = AutoApplySettings.fromMap({
        'enabled': true,
        'min_quality_score': 20,
        'max_daily_applications': 99,
        'require_low_trust': false,
      });

      expect(settings.enabled, isTrue);
      expect(settings.minQualityScore, 60);
      expect(settings.maxDailyApplications, 10);
      expect(settings.requireLowTrust, isFalse);
    });

    test('falls back when the saved value is missing or malformed', () {
      expect(AutoApplySettings.fromMap(null), const AutoApplySettings());

      final settings = AutoApplySettings.fromMap({
        'enabled': 'yes',
        'min_quality_score': 'high',
        'max_daily_applications': 'many',
      });

      expect(settings.enabled, isFalse);
      expect(settings.minQualityScore, 85);
      expect(settings.maxDailyApplications, 3);
      expect(settings.requireLowTrust, isTrue);
    });
  });
}