import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/models/job.dart';

void main() {
  group('Job provenance serialization', () {
    test('toJson includes the application/source provenance fields', () {
      const job = Job(
        id: 'job-1',
        title: 'Frontend Engineer',
        company: 'Swiftlane',
        location: 'Remote',
        salary: r'$120k',
        category: JobCategory.ready,
        matchScore: 0,
        agentAction: '',
        agentJustification: '',
        skills: [],
        missingSkills: [],
        why: 'Build dashboards.',
        employerWebsite: 'https://swiftlane.com',
        applyLink: 'https://swiftlane.com/apply/123',
        googleJobLink: 'https://google.com/jobs/123',
        sourceUrl: 'https://swiftlane.com/apply/123',
        publisher: 'LinkedIn',
        providerSource: 'jsearch',
      );

      final json = job.toJson();

      expect(json['apply_link'], 'https://swiftlane.com/apply/123');
      expect(json['google_job_link'], 'https://google.com/jobs/123');
      expect(json['source_url'], 'https://swiftlane.com/apply/123');
      expect(json['publisher'], 'LinkedIn');
      expect(json['provider_source'], 'jsearch');
      expect(json['employer_website'], 'https://swiftlane.com');
    });

    test('fromJson restores the provenance fields', () {
      final job = Job.fromJson(const {
        'id': 'job-1',
        'title': 'Frontend Engineer',
        'company': 'Swiftlane',
        'location': 'Remote',
        'salary': r'$120k',
        'category': 'ready',
        'match': 0,
        'agent_action': '',
        'agent_justification': '',
        'skills': <String>[],
        'missing': <String>[],
        'why': 'Build dashboards.',
        'employer_website': 'https://swiftlane.com',
        'apply_link': 'https://swiftlane.com/apply/123',
        'google_job_link': 'https://google.com/jobs/123',
        'source_url': 'https://swiftlane.com/apply/123',
        'publisher': 'LinkedIn',
        'provider_source': 'jsearch',
      });

      expect(job.applyLink, 'https://swiftlane.com/apply/123');
      expect(job.googleJobLink, 'https://google.com/jobs/123');
      expect(job.sourceUrl, 'https://swiftlane.com/apply/123');
      expect(job.publisher, 'LinkedIn');
      expect(job.providerSource, 'jsearch');
      expect(job.employerWebsite, 'https://swiftlane.com');
    });

    test('fromJson defaults the new fields to empty for legacy docs', () {
      // An old saved job from before the application-link work: none of the new
      // keys are present. It must still load, with empty provenance fields.
      final job = Job.fromJson(const {
        'id': 'legacy-1',
        'title': 'Backend Engineer',
        'company': 'OldCorp',
        'location': 'NYC',
        'salary': '',
        'category': 'exploration',
        'match': 0,
        'agent_action': '',
        'agent_justification': '',
        'skills': <String>[],
        'missing': <String>[],
        'why': '',
      });

      expect(job.applyLink, '');
      expect(job.googleJobLink, '');
      expect(job.sourceUrl, '');
      expect(job.publisher, '');
      expect(job.providerSource, '');
      expect(job.employerWebsite, '');
    });

    test('round-trips through toJson/fromJson without loss', () {
      const original = Job(
        id: 'job-2',
        title: 'Mobile Engineer',
        company: 'Acme',
        location: 'Taipei',
        salary: '',
        category: JobCategory.inputNeeded,
        matchScore: 0,
        agentAction: '',
        agentJustification: '',
        skills: ['Flutter'],
        missingSkills: [],
        why: '',
        applyLink: 'https://acme.example/apply',
        googleJobLink: '',
        sourceUrl: 'https://acme.example/apply',
        publisher: 'Indeed',
        providerSource: 'jsearch',
      );

      final restored = Job.fromJson(original.toJson());

      expect(restored.applyLink, original.applyLink);
      expect(restored.googleJobLink, original.googleJobLink);
      expect(restored.sourceUrl, original.sourceUrl);
      expect(restored.publisher, original.publisher);
      expect(restored.providerSource, original.providerSource);
    });
  });
}
