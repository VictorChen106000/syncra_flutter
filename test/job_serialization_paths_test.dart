import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/firestore/applications_repository.dart';
import 'package:syncra/data/models/job.dart';

const _job = Job(
  id: 'job-1',
  title: 'Frontend Engineer',
  company: 'Swiftlane',
  location: 'Remote',
  salary: r'$120k',
  category: JobCategory.ready,
  matchScore: 0,
  agentAction: '',
  agentJustification: '',
  skills: ['React'],
  missingSkills: [],
  why: 'Build dashboards.',
  employerWebsite: 'https://swiftlane.com',
  applyLink: 'https://swiftlane.com/apply/123',
  googleJobLink: 'https://google.com/jobs/123',
  sourceUrl: 'https://swiftlane.com/apply/123',
  publisher: 'LinkedIn',
  providerSource: 'jsearch',
);

void main() {
  group('ApplicationsRepository job map', () {
    test('toMap carries the provenance fields into the nested job map', () {
      final map = applicationJobToMap(_job);

      expect(map['apply_link'], 'https://swiftlane.com/apply/123');
      expect(map['google_job_link'], 'https://google.com/jobs/123');
      expect(map['source_url'], 'https://swiftlane.com/apply/123');
      expect(map['publisher'], 'LinkedIn');
      expect(map['provider_source'], 'jsearch');
      expect(map['employer_website'], 'https://swiftlane.com');
    });

    test('round-trips the provenance fields through the nested job map', () {
      final restored = applicationJobFromMap(applicationJobToMap(_job));

      expect(restored.applyLink, _job.applyLink);
      expect(restored.googleJobLink, _job.googleJobLink);
      expect(restored.sourceUrl, _job.sourceUrl);
      expect(restored.publisher, _job.publisher);
      expect(restored.providerSource, _job.providerSource);
      expect(restored.employerWebsite, _job.employerWebsite);
    });

    test('defaults provenance fields for a legacy nested job map', () {
      final restored = applicationJobFromMap(const {
        'id': 'legacy-1',
        'title': 'Backend Engineer',
        'company': 'OldCorp',
        'location': 'NYC',
        'salary': '',
        'category': 'exploration',
      });

      expect(restored.applyLink, '');
      expect(restored.googleJobLink, '');
      expect(restored.sourceUrl, '');
      expect(restored.publisher, '');
      expect(restored.providerSource, '');
      expect(restored.employerWebsite, '');
    });
  });
}
