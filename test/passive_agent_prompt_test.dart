import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/features/agent/state/passive_agent_notifier.dart';

void main() {
  group('buildPassiveAgentBriefPrompt', () {
    test('uses the requested query and remote location', () {
      final prompt = buildPassiveAgentBriefPrompt('Data Analyst Intern');

      expect(prompt, contains('"Data Analyst Intern"'));
      expect(prompt, contains('location "Remote"'));
    });

    test('searches each role separately before saving pipeline jobs', () {
      final prompt = buildPassiveAgentBriefPrompt('Product Designer');

      expect(prompt, contains('Call search_jobs once for EACH distinct'));
      expect(prompt, contains('Call save_to_pipeline'));
      expect(
        prompt.indexOf('search_jobs'),
        lessThan(prompt.indexOf('save_to_pipeline')),
      );
      expect(prompt, contains('Do NOT combine all roles into a single'));
    });

    test('caps the brief at five saved jobs', () {
      final prompt = buildPassiveAgentBriefPrompt('UX Designer');

      expect(prompt, contains('Save at most 5 jobs.'));
      expect(prompt, contains('If there are fewer than 5 good matches'));
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

    test('handles the no-resume fallback path', () {
      final prompt = buildPassiveAgentBriefPrompt('Business Analyst');

      expect(prompt, contains('If read_resume returns no resume'));
      expect(prompt, contains('skip match_jobs'));
      expect(prompt, contains('category "exploration"'));
    });
  });
}
