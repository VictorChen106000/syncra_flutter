import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/models/job.dart';
import 'package:syncra/features/jobs/services/job_trust_guard.dart';

void main() {
  group('evaluateJobTrust', () {
    test('returns low risk when no obvious red flags are present', () {
      final result = evaluateJobTrust(
        _job(
          company: 'Acme Studio',
          title: 'Junior Product Designer',
          why:
              'Join a small product team to design onboarding flows, improve user research synthesis, and collaborate with engineers on mobile app features.',
        ),
      );

      expect(result.riskLevel, 'low');
      expect(result.riskLabel, 'Looks normal');
      expect(result.signals, isEmpty);
      expect(result.signalsCount, 0);
      expect(result.needsVerification, isFalse);
      expect(result.summary, 'Looks normal · no obvious red flags');
      expect(result.safeNextStep, contains('Still verify'));
    });

    test('returns medium risk for multiple verification signals', () {
      final result = evaluateJobTrust(
        _job(
          company: 'Confidential',
          title: 'Remote Assistant',
          why: 'Short posting.',
        ),
      );

      expect(result.riskLevel, 'medium');
      expect(result.riskLabel, 'Needs verification');
      expect(result.needsVerification, isTrue);
      expect(result.signalsCount, greaterThanOrEqualTo(2));
      expect(
        result.signals.map((signal) => signal['label']),
        containsAll(['Generic company identity', 'Thin job description']),
      );
      expect(result.safeNextStep, contains('Verify the company site'));
    });

    test('returns high risk when red-flag wording is present', () {
      final result = evaluateJobTrust(
        _job(
          company: 'Northstar Careers',
          title: 'Operations Coordinator',
          why:
              'This role coordinates remote onboarding, handles candidate communication, and asks applicants to buy gift card materials before their first work assignment.',
        ),
      );

      expect(result.riskLevel, 'high');
      expect(result.riskLabel, 'High risk');
      expect(result.needsVerification, isTrue);
      expect(
        result.signals,
        contains(
          allOf([
            containsPair('severity', 'high'),
            containsPair('label', 'Red-flag wording'),
          ]),
        ),
      );
      expect(result.safeNextStep, contains('Do not send personal documents'));
    });

    test('uses singular summary wording for one signal', () {
      final result = evaluateJobTrust(
        _job(
          company: 'Acme Studio',
          title: 'Product Design Intern',
          why: 'Too short.',
        ),
      );

      expect(result.signalsCount, 1);
      expect(result.summary, 'Looks normal · 1 signal');
    });
  });
}

Job _job({
  required String company,
  required String title,
  required String why,
}) {
  return Job(
    id: 'job_test',
    title: title,
    company: company,
    location: 'Remote',
    salary: '',
    category: JobCategory.ready,
    matchScore: 0,
    agentAction: '',
    agentJustification: '',
    skills: const [],
    missingSkills: const [],
    why: why,
  );
}
