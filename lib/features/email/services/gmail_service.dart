import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

/// One file attached to an outgoing email.
///
/// Bytes, not a file path: resume PDFs live in Firebase Cloud Storage
/// (api-contract §0), so there is no local path to point at. Callers fetch
/// the bytes (e.g. `ResumesRepository.downloadBytes`) and hand them here.
class EmailAttachment {
  const EmailAttachment({
    required this.filename,
    required this.bytes,
    this.mimeType = 'application/pdf',
  });

  final String filename;
  final Uint8List bytes;
  final String mimeType;
}

/// Sends email from the signed-in user's **own** Gmail account.
///
/// Auth model — `google_sign_in` v7 splits the old single step in two:
///   1. *Authentication* (identity) happens once at sign-in.
///   2. *Authorization* (a per-scope OAuth access token) is requested
///      on demand. This service asks the account's `authorizationClient`
///      for the [sendScope] token, prompting the user the first time.
///
/// We deliberately skip the `googleapis` / `googleapis_auth` packages the
/// brief suggested: v7 hands us a bare access-token string with no exposed
/// expiry, which makes building `googleapis_auth.AccessCredentials` awkward.
/// A raw POST to the documented `users.messages.send` endpoint is lighter
/// and behaves identically. If the team later needs more Gmail surface,
/// swapping to `GmailApi` with a custom auth client is the upgrade path.
///
/// Send-only: this never requests `gmail.readonly`. Adding read scope needs
/// a team vote per api-contract §11.5.
class GmailService {
  GmailService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Scope for sending mail outright (`messages.send`).
  static const String sendScope = 'https://www.googleapis.com/auth/gmail.send';

  /// Scope for creating drafts (`drafts.create`). `gmail.send` alone is not
  /// enough to write a draft, so the draft path requests this instead.
  static const String composeScope =
      'https://www.googleapis.com/auth/gmail.compose';

  static const String _sendEndpoint =
      'https://gmail.googleapis.com/gmail/v1/users/me/messages/send';

  static const String _draftEndpoint =
      'https://gmail.googleapis.com/gmail/v1/users/me/drafts';

  static const Duration _httpTimeout = Duration(seconds: 30);

  /// Sends an email and returns the Gmail message id.
  ///
  /// Throws [GmailException] when the user is not signed in with Google,
  /// declines the send permission, or the Gmail API rejects the request.
  Future<String> send({
    required String to,
    required String subject,
    required String body,
    List<EmailAttachment> attachments = const [],
  }) async {
    final recipient = to.trim();
    if (recipient.isEmpty) {
      throw GmailException('No recipient address.');
    }

    final token = await _accessToken(sendScope);
    final raw = _buildMimeMessage(
      to: recipient,
      subject: subject,
      body: body,
      attachments: attachments,
    );

    final decoded = await _post(
      endpoint: _sendEndpoint,
      token: token,
      payload: {'raw': raw},
    );
    final id = (decoded['id'] as String?)?.trim();
    if (id == null || id.isEmpty) {
      throw GmailException('Gmail accepted the send but returned no id.');
    }
    return id;
  }

  /// Creates a draft in the signed-in user's Gmail and returns the draft id.
  ///
  /// Nothing is sent — the draft lands in the user's Drafts folder for them to
  /// review and send from Gmail themselves. Uses [composeScope]; the user is
  /// prompted to grant it the first time.
  ///
  /// Throws [GmailException] when the user is not signed in, declines the
  /// permission, or the Gmail API rejects the request.
  Future<String> createDraft({
    required String to,
    required String subject,
    required String body,
    List<EmailAttachment> attachments = const [],
  }) async {
    final recipient = to.trim();
    if (recipient.isEmpty) {
      throw GmailException('No recipient address.');
    }

    final token = await _accessToken(composeScope);
    final raw = _buildMimeMessage(
      to: recipient,
      subject: subject,
      body: body,
      attachments: attachments,
    );

    // drafts.create wraps the raw message in a `message` object, unlike send.
    final decoded = await _post(
      endpoint: _draftEndpoint,
      token: token,
      payload: {
        'message': {'raw': raw},
      },
    );
    final id = (decoded['id'] as String?)?.trim();
    if (id == null || id.isEmpty) {
      throw GmailException('Gmail accepted the draft but returned no id.');
    }
    return id;
  }

  /// POSTs [payload] as JSON to a Gmail endpoint and returns the decoded body,
  /// translating transport and API errors into [GmailException].
  Future<Map<String, dynamic>> _post({
    required String endpoint,
    required String token,
    required Map<String, dynamic> payload,
  }) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(endpoint),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(_httpTimeout);
    } catch (e) {
      throw GmailException('Gmail request failed: $e');
    }

    if (response.statusCode != 200) {
      throw GmailException(
        _extractError(response.body, response.statusCode),
        statusCode: response.statusCode,
      );
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw GmailException('Could not parse the Gmail response.');
    }
  }

  /// Obtains an OAuth access token carrying [scope], prompting the user to
  /// grant it the first time. The grant triggers Google's unverified-app
  /// warning — expected for the class demo (api-contract §5.3).
  Future<String> _accessToken(String scope) async {
    if (kIsWeb) {
      // Web sign-in goes through Firebase's popup, not `google_sign_in`, so
      // the `authorizationClient` path below isn't wired there. Sending from
      // the web build is out of scope for v1.
      throw GmailException(
        'Sending email is only supported on the mobile app in this build.',
      );
    }

    GoogleSignInAccount? account;
    try {
      account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } catch (_) {
      account = null;
    }
    if (account == null) {
      throw GmailException('Sign in with Google to send email.');
    }

    final auth = account.authorizationClient;

    // Reuse an existing grant if the user already approved the scope;
    // otherwise prompt for it.
    var authorization = await auth.authorizationForScopes([scope]);
    if (authorization == null) {
      try {
        authorization = await auth.authorizeScopes([scope]);
      } on GoogleSignInException catch (e) {
        throw GmailException('Gmail permission was not granted (${e.code.name}).');
      }
    }

    final token = authorization.accessToken;
    if (token.isEmpty) {
      throw GmailException('Gmail permission was not granted.');
    }
    return token;
  }

  /// Builds an RFC 2822 message and returns it base64url-encoded, the form
  /// the Gmail `raw` field expects. Text and attachment parts are both
  /// base64-encoded so UTF-8 bodies and binary PDFs survive transport.
  String _buildMimeMessage({
    required String to,
    required String subject,
    required String body,
    required List<EmailAttachment> attachments,
  }) {
    const crlf = '\r\n';
    final headers = StringBuffer()
      ..write('To: $to$crlf')
      ..write('Subject: ${_encodeHeaderValue(subject.trim())}$crlf')
      ..write('MIME-Version: 1.0$crlf');

    final message = StringBuffer();
    if (attachments.isEmpty) {
      message
        ..write(headers)
        ..write('Content-Type: text/plain; charset="UTF-8"$crlf')
        ..write('Content-Transfer-Encoding: base64$crlf')
        ..write(crlf)
        ..write(_chunk(base64.encode(utf8.encode(body))));
    } else {
      final boundary = 'syncra_${DateTime.now().microsecondsSinceEpoch}';
      message
        ..write(headers)
        ..write('Content-Type: multipart/mixed; boundary="$boundary"$crlf')
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: text/plain; charset="UTF-8"$crlf')
        ..write('Content-Transfer-Encoding: base64$crlf')
        ..write(crlf)
        ..write(_chunk(base64.encode(utf8.encode(body))))
        ..write(crlf);
      for (final att in attachments) {
        final name = _encodeHeaderValue(att.filename);
        message
          ..write('--$boundary$crlf')
          ..write('Content-Type: ${att.mimeType}; name="$name"$crlf')
          ..write('Content-Transfer-Encoding: base64$crlf')
          ..write('Content-Disposition: attachment; filename="$name"$crlf')
          ..write(crlf)
          ..write(_chunk(base64.encode(att.bytes)))
          ..write(crlf);
      }
      message.write('--$boundary--');
    }

    return base64Url.encode(utf8.encode(message.toString()));
  }

  /// RFC 2047 encoded-word for non-ASCII header values (e.g. an emoji in the
  /// subject). Pure-ASCII values pass through untouched.
  String _encodeHeaderValue(String value) {
    final isAscii = value.codeUnits.every((c) => c < 128);
    if (isAscii) return value;
    return '=?UTF-8?B?${base64.encode(utf8.encode(value))}?=';
  }

  /// MIME caps encoded lines at 76 chars; wrap to keep strict servers happy.
  String _chunk(String base64Text) {
    const width = 76;
    if (base64Text.length <= width) return base64Text;
    final buf = StringBuffer();
    for (var i = 0; i < base64Text.length; i += width) {
      final end = (i + width < base64Text.length) ? i + width : base64Text.length;
      if (i > 0) buf.write('\r\n');
      buf.write(base64Text.substring(i, end));
    }
    return buf.toString();
  }

  String _extractError(String body, int status) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final error = decoded['error'];
      if (error is Map && error['message'] is String) {
        return 'Gmail send failed: ${error['message']}';
      }
    } catch (_) {
      // Fall through to the generic message.
    }
    return 'Gmail send failed (HTTP $status).';
  }

  void dispose() => _client.close();
}

/// Raised when a Gmail send cannot be completed.
class GmailException implements Exception {
  GmailException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'GmailException($statusCode): $message';
}
