import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncra/features/email/models/recipient_resolution.dart';
import 'package:syncra/features/email/services/company_contact_discovery_service.dart';

void main() {
  group('CompanyContactDiscoveryService', () {
    test(
      'returns recipient resolution from a successful function response',
      () async {
        final service = CompanyContactDiscoveryService(
          endpoint: Uri.parse('https://example.test/companyContactDiscovery'),
          headersProvider: () async => {'authorization': 'Bearer test'},
          client: MockClient((request) async {
            expect(request.method, 'POST');
            expect(request.url.path, '/companyContactDiscovery');
            expect(request.body, contains('"company":"Acme"'));
            expect(request.body, contains('"website":"https://acme.io"'));
            expect(
              request.body,
              contains('"applyLink":"https://acme.io/jobs"'),
            );

            return http.Response(
              '''
{
  "email": "careers@acme.io",
  "domain": "acme.io",
  "confidence": "high",
  "source": "officialCompanyWebsite",
  "label": "Found on official site",
  "sourceUrl": "https://acme.io/jobs",
  "reason": "Found careers@acme.io on the official careers page.",
  "canAutoSend": true,
  "requiresUserConfirmation": false
}
''',
              200,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final result = await service.resolve(
          company: 'Acme',
          website: 'https://acme.io',
          applyLink: 'https://acme.io/jobs',
        );

        expect(result, isNotNull);
        expect(result!.email, 'careers@acme.io');
        expect(result.domain, 'acme.io');
        expect(result.confidence, RecipientConfidence.high);
        expect(result.source, RecipientSource.officialCompanyWebsite);
        expect(result.canAutoSend, isTrue);
        expect(result.requiresUserConfirmation, isFalse);
      },
    );

    test('returns null on non-200 response', () async {
      final service = CompanyContactDiscoveryService(
        endpoint: Uri.parse('https://example.test/companyContactDiscovery'),
        headersProvider: () async => {'authorization': 'Bearer test'},
        client: MockClient((request) async {
          return http.Response('not found', 404);
        }),
      );

      final result = await service.resolve(
        company: 'Acme',
        website: 'https://acme.io',
      );

      expect(result, isNull);
    });

    test('returns null on invalid JSON response', () async {
      final service = CompanyContactDiscoveryService(
        endpoint: Uri.parse('https://example.test/companyContactDiscovery'),
        headersProvider: () async => {'authorization': 'Bearer test'},
        client: MockClient((request) async {
          return http.Response('not json', 200);
        }),
      );

      final result = await service.resolve(
        company: 'Acme',
        website: 'https://acme.io',
      );

      expect(result, isNull);
    });

    test('returns null when no useful input is provided', () async {
      var called = false;

      final service = CompanyContactDiscoveryService(
        endpoint: Uri.parse('https://example.test/companyContactDiscovery'),
        headersProvider: () async => {'authorization': 'Bearer test'},
        client: MockClient((request) async {
          called = true;
          return http.Response('{}', 200);
        }),
      );

      final result = await service.resolve(company: '');

      expect(result, isNull);
      expect(called, isFalse);
    });
  });
}
