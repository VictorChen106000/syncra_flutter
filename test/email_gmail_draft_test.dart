import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:syncra/features/email/services/email_send_service.dart';
import 'package:syncra/features/email/services/gmail_service.dart';

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
}
