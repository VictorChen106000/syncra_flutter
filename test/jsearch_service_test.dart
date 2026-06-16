import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/services/jsearch_service.dart';

/// A representative JSearch `data[]` record, trimmed to the fields the mapper
/// reads. No secrets — purely synthetic fixture data.
Map<String, dynamic> _raw({
  String? applyLink = 'https://boards.greenhouse.io/acme/jobs/42/apply',
  String? googleLink = 'https://www.google.com/search?q=acme+frontend',
  String? publisher = 'Greenhouse',
  String? website = 'https://acme.example',
}) {
  return {
    'job_title': 'Frontend Engineer',
    'employer_name': 'Acme',
    'employer_website': website,
    'job_apply_link': applyLink,
    'job_google_link': googleLink,
    'job_publisher': publisher,
    'job_city': 'Taipei',
    'job_country': 'TW',
    'job_description': 'Build delightful UIs.',
  };
}

void main() {
  group('JSearchService.jobFromJSearchRecord', () {
    test(
      'maps job_apply_link to applyLink and job_google_link to googleJobLink',
      () {
        final job = JSearchService.jobFromJSearchRecord(_raw())!;

        expect(
          job.applyLink,
          'https://boards.greenhouse.io/acme/jobs/42/apply',
        );
        expect(
          job.googleJobLink,
          'https://www.google.com/search?q=acme+frontend',
        );
      },
    );

    test('sourceUrl prefers the apply link when present', () {
      final job = JSearchService.jobFromJSearchRecord(_raw())!;
      expect(job.sourceUrl, job.applyLink);
    });

    test('sourceUrl falls back to the Google link when no apply link', () {
      final job = JSearchService.jobFromJSearchRecord(_raw(applyLink: null))!;

      expect(job.applyLink, '');
      expect(job.sourceUrl, 'https://www.google.com/search?q=acme+frontend');
    });

    test('maps job_publisher to publisher and stamps providerSource', () {
      final job = JSearchService.jobFromJSearchRecord(_raw())!;

      expect(job.publisher, 'Greenhouse');
      expect(job.providerSource, 'jsearch');
    });

    test('keeps employer_website separate from the apply/source links', () {
      final job = JSearchService.jobFromJSearchRecord(_raw())!;

      expect(job.employerWebsite, 'https://acme.example');
      expect(job.employerWebsite, isNot(job.applyLink));
    });

    test('rejects a record with no apply and no Google link', () {
      final job = JSearchService.jobFromJSearchRecord(
        _raw(applyLink: null, googleLink: null),
      );
      expect(job, isNull);
    });

    test('produces a stable deterministic id from the source url', () {
      final a = JSearchService.jobFromJSearchRecord(_raw())!;
      final b = JSearchService.jobFromJSearchRecord(_raw())!;

      expect(a.id, b.id);
      expect(a.id, startsWith('job_'));
    });
  });
}
