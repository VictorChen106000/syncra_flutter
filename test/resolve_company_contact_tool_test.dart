import 'package:flutter_test/flutter_test.dart';
import 'package:syncra/data/firestore/company_contacts_repository.dart';
import 'package:syncra/features/agent_chat/tools/builtin_tools.dart';
import 'package:syncra/features/email/models/recipient_resolution.dart';
import 'package:syncra/features/email/services/company_contact_discovery_service.dart';

void main() {
  // App ships with a demo-inbox override; this test checks real resolution.

  test(
    'resolve_company_contact tool helper returns recipient metadata',
    () async {
      final result = await resolveCompanyContactToolResult(
        'Linear',
        website: 'https://linear.app',
      );

      expect(result.isError, isFalse);
      final data = result.data as Map<String, dynamic>;
      expect(data['email'], 'careers@linear.app');
      expect(data['domain'], 'linear.app');
      expect(data['confidence'], RecipientConfidence.low.name);
      expect(data['source'], RecipientSource.guessedPattern.name);
      expect(data['canAutoSend'], isFalse);
      expect(data['requiresUserConfirmation'], isTrue);
    },
  );

  test(
    'resolve_company_contact returns non-fallback official discovery metadata',
    () async {
      final result = await resolveCompanyContactToolResult(
        'Acme',
        website: 'https://acme.io',
        contacts: _FakeContacts(),
        discovery: const _FakeDiscovery(
          RecipientResolution(
            email: 'talent@acme.io',
            domain: 'acme.io',
            confidence: RecipientConfidence.high,
            source: RecipientSource.officialCompanyWebsite,
            label: 'Found on official site',
            sourceUrl: 'https://acme.io/jobs',
            reason: 'Found talent@acme.io on an official company page.',
            canAutoSend: true,
            requiresUserConfirmation: false,
          ),
        ),
      );

      expect(result.isError, isFalse);
      final data = result.data as Map<String, dynamic>;
      expect(data['email'], 'talent@acme.io');
      expect(data['recipient'], 'talent@acme.io');
      expect(data['domain'], 'acme.io');
      expect(data['confidence'], RecipientConfidence.high.name);
      expect(data['source'], RecipientSource.officialCompanyWebsite.name);
      expect(data['sourceUrl'], 'https://acme.io/jobs');
      expect(data['canAutoSend'], isTrue);
      expect(data['requiresUserConfirmation'], isFalse);
    },
  );
}

class _FakeContacts implements CompanyContactsRepository {
  @override
  Future<String?> lookupEmail(String domain) async => null;

  @override
  Future<RecipientResolution?> lookupResolution(String domain) async => null;

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
