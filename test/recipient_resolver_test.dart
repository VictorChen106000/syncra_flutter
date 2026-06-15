import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/firestore/company_contacts_repository.dart';
import 'package:syncra/features/email/models/recipient_resolution.dart';
import 'package:syncra/features/email/services/company_contact_discovery_service.dart';
import 'package:syncra/features/email/services/recipient_resolver.dart';

void main() {
  // The app ships with a demo-inbox override (so Autopilot delivers live);
  // these tests exercise *real* per-company resolution, so clear it first.
  setUp(() => demoRecipientOverride = '');

  group('resolveRecipientAsync', () {
    test(
      'confirmed Firestore contact wins over discovery and guessed fallback',
      () async {
        final cache = RecipientResolution.confirmed(
          email: 'talent@acme.io',
          domain: 'acme.io',
          reason: 'Seeded confirmed contact.',
        );
        final discovered = RecipientResolution(
          email: 'jobs@acme.io',
          domain: 'acme.io',
          confidence: RecipientConfidence.high,
          source: RecipientSource.officialCompanyWebsite,
          label: 'Found on official site',
          sourceUrl: 'https://acme.io/contact',
          reason: 'Found on the official website.',
          canAutoSend: true,
          requiresUserConfirmation: false,
        );

        final resolution = await resolveRecipientAsync(
          'Acme',
          website: 'https://www.acme.io/jobs',
          contacts: _FakeContacts({'acme.io': cache}),
          discovery: _FakeDiscovery(discovered),
        );

        expect(resolution.email, 'talent@acme.io');
        expect(resolution.confidence, RecipientConfidence.confirmed);
        expect(resolution.source, RecipientSource.confirmedCache);
        expect(resolution.canAutoSend, isTrue);
      },
    );

    test('employerWebsite domain beats company-name slug', () async {
      final resolution = await resolveRecipientAsync(
        'Totally Different Name',
        website: 'https://www.real-company.dev/openings',
        contacts: _FakeContacts(),
        discovery: const CompanyContactDiscoveryService(),
      );

      expect(resolution.email, 'careers@real-company.dev');
      expect(resolution.domain, 'real-company.dev');
      expect(
        resolveRecipient('Totally Different Name'),
        'careers@totallydifferentname.com',
      );
    });

    test('guessed fallback is low confidence and cannot auto-send', () async {
      final resolution = await resolveRecipientAsync(
        'Linear',
        website: 'https://linear.app',
        contacts: _FakeContacts(),
        discovery: const CompanyContactDiscoveryService(),
      );

      expect(resolution.email, 'careers@linear.app');
      expect(resolution.confidence, RecipientConfidence.low);
      expect(resolution.source, RecipientSource.guessedPattern);
      expect(resolution.canAutoSend, isFalse);
      expect(resolution.requiresUserConfirmation, isTrue);
    });

    test(
      'missing company and website returns none with direct send disabled',
      () async {
        final resolution = await resolveRecipientAsync(
          '',
          contacts: _FakeContacts(),
          discovery: const CompanyContactDiscoveryService(),
        );

        expect(resolution.email, isEmpty);
        expect(resolution.confidence, RecipientConfidence.none);
        expect(resolution.source, RecipientSource.none);
        expect(resolution.canAutoSend, isFalse);
        expect(resolution.requiresUserConfirmation, isTrue);
      },
    );
  });
}

class _FakeContacts implements CompanyContactsRepository {
  _FakeContacts([Map<String, RecipientResolution>? resolutions])
    : resolutions = resolutions ?? const {};

  final Map<String, RecipientResolution> resolutions;

  @override
  Future<String?> lookupEmail(String domain) async =>
      (await lookupResolution(domain))?.email;

  @override
  Future<RecipientResolution?> lookupResolution(String domain) async =>
      resolutions[domain.trim().toLowerCase()];

  @override
  Future<void> markRejected(String domain) async {}

  @override
  Future<void> saveConfirmedEmail({
    required String domain,
    required String email,
    String? company,
    String? uid,
  }) async {}

  @override
  Future<void> saveConfirmedResolution(
    RecipientResolution resolution, {
    String? company,
    String? uid,
  }) async {}
}

class _FakeDiscovery extends CompanyContactDiscoveryService {
  const _FakeDiscovery(this.result);

  final RecipientResolution? result;

  @override
  Future<RecipientResolution?> resolve({
    required String company,
    String? website,
    String? applyLink,
  }) async => result;
}
