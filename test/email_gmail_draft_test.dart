import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncra/features/email/services/email_send_service.dart';
import 'package:syncra/features/email/services/gmail_service.dart';
import 'package:syncra/data/firestore/company_contacts_repository.dart';
import 'package:syncra/features/email/models/recipient_resolution.dart';

void main() {
  test(
    'EmailSendService rejects sendConfirmed without a confirmation token',
    () async {
      await expectLater(
        EmailSendService.instance.sendConfirmed(
          confirmationToken: null,
          to: 'recruiting@example.com',
          subject: 'Hello',
          body: 'Thanks for reviewing my application.',
        ),
        throwsA(isA<EmailNotConfirmedException>()),
      );
    },
  );

  test(
    'GmailService.createDraft uses compose scope and draft endpoint',
    () async {
      String? requestedScope;
      http.Request? capturedRequest;
      Map<String, dynamic>? capturedPayload;

      final client = MockClient((request) async {
        capturedRequest = request;
        capturedPayload = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'id': 'draft-123'}), 200);
      });

      final service = GmailService(
        client: client,
        accessTokenProvider: (scope) async {
          requestedScope = scope;
          return 'test-access-token';
        },
      );
      addTearDown(service.dispose);

      final draftId = await service.createDraft(
        to: 'recruiting@example.com',
        subject: 'Product design role',
        body: 'Hi team,\n\nI would love to talk.',
        attachments: [
          EmailAttachment(
            filename: 'Resume.pdf',
            bytes: Uint8List.fromList([1, 2, 3, 4]),
          ),
        ],
      );

      expect(draftId, 'draft-123');
      expect(requestedScope, GmailService.composeScope);
      expect(
        capturedRequest?.url.toString(),
        'https://gmail.googleapis.com/gmail/v1/users/me/drafts',
      );
      expect(
        capturedRequest?.headers['Authorization'],
        'Bearer test-access-token',
      );
      expect(capturedPayload, contains('message'));

      final message = capturedPayload!['message'] as Map<String, dynamic>;
      final raw = message['raw'] as String;
      final mime = utf8.decode(base64Url.decode(base64Url.normalize(raw)));

      expect(mime, contains('To: recruiting@example.com'));
      expect(mime, contains('Subject: Product design role'));
      expect(mime, contains('Content-Disposition: attachment'));
      expect(mime, contains('Resume.pdf'));
    },
  );

  test('email review draft mode has no web-only reviewed fallback', () {
    final source = File(
      'lib/features/email/presentation/email_review_page.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('Mark draft reviewed')));
    expect(source, isNot(contains('web-reviewed-')));
    expect(source, isNot(contains('_isWebDraftFallback')));
  });

  test('source does not request Gmail read scope', () {
    final dartFiles = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains('https://www.googleapis.com/auth/gmail.readonly')),
        reason: '${file.path} must not request Gmail read scope.',
      );
    }
  });

  test(
    'EmailSendService.createDraft learns user-reviewed recipients',
    () async {
      final contacts = _FakeCompanyContactsRepository();
      final gmail = _mockDraftGmailService('draft-123');

      final service = EmailSendService.instance;
      service.debugOverrideDependencies(gmail: gmail, contacts: contacts);

      addTearDown(() {
        service.debugOverrideDependencies();
        gmail.dispose();
      });

      final draftId = await service.createDraft(
        to: 'talent@acme.io',
        subject: 'Application',
        body: 'Hello team.',
        contactDomain: 'acme.io',
        company: 'Acme',
        uid: 'user-1',
        learnRecipient: true,
      );

      expect(draftId, 'draft-123');
      expect(contacts.saved, hasLength(1));
      expect(contacts.saved.single.domain, 'acme.io');
      expect(contacts.saved.single.email, 'talent@acme.io');
      expect(contacts.saved.single.company, 'Acme');
      expect(contacts.saved.single.uid, 'user-1');
    },
  );

  test(
    'EmailSendService.createDraft can skip learning uncertain recipients',
    () async {
      final contacts = _FakeCompanyContactsRepository();
      final gmail = _mockDraftGmailService('draft-456');

      final service = EmailSendService.instance;
      service.debugOverrideDependencies(gmail: gmail, contacts: contacts);

      addTearDown(() {
        service.debugOverrideDependencies();
        gmail.dispose();
      });

      final draftId = await service.createDraft(
        to: 'careers@unknown-example.com',
        subject: 'Application',
        body: 'Hello team.',
        contactDomain: 'unknown-example.com',
        company: 'Unknown Example',
        uid: 'user-1',
        learnRecipient: false,
      );

      expect(draftId, 'draft-456');
      expect(contacts.saved, isEmpty);
    },
  );
}

GmailService _mockDraftGmailService(String draftId) {
  return GmailService(
    client: MockClient((request) async {
      return http.Response(jsonEncode({'id': draftId}), 200);
    }),
    accessTokenProvider: (_) async => 'test-access-token',
  );
}

class _FakeCompanyContactsRepository implements CompanyContactsRepository {
  final saved =
      <({String domain, String email, String? company, String? uid})>[];

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
  }) async {
    saved.add((domain: domain, email: email, company: company, uid: uid));
  }

  @override
  Future<void> saveConfirmedResolution(
    RecipientResolution resolution, {
    String? company,
    String? uid,
  }) async {
    saved.add((
      domain: resolution.domain,
      email: resolution.email,
      company: company,
      uid: uid,
    ));
  }
}
