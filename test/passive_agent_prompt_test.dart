import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/agent/state/passive_agent_notifier.dart';

void main() {
  group('buildPassiveAgentBriefPrompt', () {
    test('uses the requested query and remote location', () {
      final prompt = buildPassiveAgentBriefPrompt('Data Analyst Intern');

      expect(prompt, contains('search_jobs with query "Data Analyst Intern"'));
      expect(prompt, contains('location "Remote"'));
    });

    test('requires Trust Guard before saving pipeline jobs', () {
      final prompt = buildPassiveAgentBriefPrompt('Product Designer');

      expect(prompt, contains('Call check_job_risk'));
      expect(prompt, contains('Call save_to_pipeline'));
      expect(
        prompt.indexOf('check_job_risk'),
        lessThan(prompt.indexOf('save_to_pipeline')),
      );
      expect(
        prompt,
        contains(
          'Run check_job_risk before every save_to_pipeline call when a job_id is available.',
        ),
      );
    });

    test('skips medium and high risk jobs during the brief', () {
      final prompt = buildPassiveAgentBriefPrompt('UX Designer');

      expect(prompt, contains('Needs verification'));
      expect(prompt, contains('High risk'));
      expect(prompt, contains('do not save that job during the brief'));
      expect(prompt, contains('If there are fewer than 5 low-risk jobs'));
    });

    test('uses honest Trust Guard wording instead of safety guarantees', () {
      final prompt = buildPassiveAgentBriefPrompt('Frontend Developer');

      expect(prompt, contains('quick red-flag screen only'));
      expect(
        prompt,
        contains('never describe a job as safe, certified, or guaranteed'),
      );
    });

    test('does not perform outreach or ask user questions', () {
      final prompt = buildPassiveAgentBriefPrompt('Marketing Intern');

      expect(prompt, contains('Do not call tailor_resume.'));
      expect(prompt, contains('Do not call draft_email.'));
      expect(prompt, contains('Do not call send_email.'));
      expect(
        prompt,
        contains('Do not ask the user questions during this brief'),
      );
    });

    test('still runs Trust Guard in the no-resume fallback path', () {
      final prompt = buildPassiveAgentBriefPrompt('Business Analyst');

      expect(prompt, contains('If read_resume returns no resume'));
      expect(prompt, contains('skip match_jobs'));
      expect(prompt, contains('category "exploration"'));
      expect(prompt, contains('still run Trust Guard before saving'));
    });
  });
}
