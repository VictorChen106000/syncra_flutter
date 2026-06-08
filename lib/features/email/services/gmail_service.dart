import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
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

/// Sends email and creates drafts from the signed-in user's **own** Gmail
/// account.
///
/// Auth model — `google_sign_in` v7 splits the old single step in two:
///   1. *Authentication* (identity) happens once at sign-in.
///   2. *Authorization* (a per-scope OAuth access token) is requested
///      on demand. This service asks the account's `authorizationClient`
///      for the draft/send token it needs, prompting the user the first time.
///
/// We deliberately skip the `googleapis` / `googleapis_auth` packages the
/// brief suggested: v7 hands us a bare access-token string with no exposed
/// expiry, which makes building `googleapis_auth.AccessCredentials` awkward.
/// A raw POST to the documented `users.messages.send` endpoint is lighter
/// and behaves identically. If the team later needs more Gmail surface,
/// swapping to `GmailApi` with a custom auth client is the upgrade path.
///
/// Draft/send only: this never requests `gmail.readonly`. Adding read scope
/// needs a team vote per api-contract §11.5.
class GmailService {
  GmailService({
    http.Client? client,
    @visibleForTesting
    Future<String> Function(String scope)? accessTokenProvider,
  }) : _client = client ?? http.Client(),
       _accessTokenProvider = accessTokenProvider;

  final http.Client _client;
  final Future<String> Function(String scope)? _accessTokenProvider;

  /// Scope for sending mail outright (`messages.send`).
  static const String sendScope = 'https://www.googleapis.com/auth/gmail.send';

  /// Scope for creating drafts (`drafts.create`). `gmail.send` alone is not
  /// enough to write a draft, so the draft path requests this instead.
  static const String composeScope =
      'https://www.googleapis.com/auth/gmail.compose';

  /// The grants Syncra asks for up front on the "Link Gmail" screen: drafting
  /// ([composeScope]) and sending ([sendScope]). Bundling both into one prompt
  /// means the agent can later draft *and* send outreach without ever stopping
  /// to ask again.
  static const List<String> _linkScopes = [composeScope, sendScope];

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
    if (kIsWeb) {
      throw GmailException(
        'Sending email from the web is not supported yet. Save a Gmail draft '
        'and send it from Gmail.',
      );
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

  /// Pre-authorizes the Gmail scopes Syncra needs ([_linkScopes]) so the agent
  /// can later draft and send outreach without interrupting the user with an
  /// OAuth prompt mid-task. Surfaced as the "Link Gmail" onboarding step.
  ///
  /// Returns `true` once the grant is in place (or was already approved), and
  /// `false` — never throwing — when the user declines, isn't signed in with
  /// Google, or is on web (where draft save asks for compose permission on
  /// demand through Firebase Auth). The caller treats linking as optional and
  /// proceeds regardless.
  Future<bool> link() async {
    if (kIsWeb) return false;

    GoogleSignInAccount? account;
    try {
      account = await GoogleSignIn.instance.attemptLightweightAuthentication();
    } catch (_) {
      account = null;
    }
    if (account == null) return false;

    final auth = account.authorizationClient;
    try {
      // Honour an existing grant; otherwise prompt for both scopes at once.
      final authorization =
          await auth.authorizationForScopes(_linkScopes) ??
          await auth.authorizeScopes(_linkScopes);
      return authorization.accessToken.isNotEmpty;
    } on GoogleSignInException {
      return false;
    }
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
    final override = _accessTokenProvider;
    if (override != null) {
      final token = (await override(scope)).trim();
      if (token.isEmpty) {
        throw GmailException('Gmail permission was not granted.');
      }
      return token;
    }

    if (kIsWeb) {
      return _webAccessToken(scope);
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
        throw GmailException(
          'Gmail permission was not granted (${e.code.name}).',
        );
      }
    }

    final token = authorization.accessToken;
    if (token.isEmpty) {
      throw GmailException('Gmail permission was not granted.');
    }
    return token;
  }

  /// Web obtains provider OAuth tokens through Firebase Auth popups. This is
  /// intentionally compose-only for now: web draft creation is in scope, web
  /// sending is not.
  Future<String> _webAccessToken(String scope) async {
    if (scope == sendScope) {
      throw GmailException(
        'Sending email from the web is not supported yet. Save a Gmail draft '
        'and send it from Gmail.',
      );
    }

    final provider = GoogleAuthProvider()
      ..addScope('email')
      ..addScope('profile')
      ..addScope(scope);

    final UserCredential credential;
    try {
      final auth = FirebaseAuth.instance;
      final currentUser = auth.currentUser;
      credential = currentUser != null
          ? await currentUser.reauthenticateWithPopup(provider)
          : await auth.signInWithPopup(provider);
    } on FirebaseAuthException catch (e) {
      throw GmailException(_webAuthErrorMessage(e));
    } catch (_) {
      throw GmailException(
        'Could not get Gmail permission. Try linking Gmail again.',
      );
    }

    final token = credential.credential?.accessToken?.trim();
    if (token == null || token.isEmpty) {
      throw GmailException(
        'Could not get Gmail permission. Try linking Gmail again.',
      );
    }
    return token;
  }

  String _webAuthErrorMessage(FirebaseAuthException e) {
    return switch (e.code) {
      'popup-closed-by-user' ||
      'cancelled-popup-request' ||
      'web-context-cancelled' =>
        'Gmail permission was not granted. Try again when you are ready.',
      'user-mismatch' ||
      'account-exists-with-different-credential' ||
      'credential-already-in-use' ||
      'email-already-in-use' =>
        'Choose the same Google account you use for Syncra, then try again.',
      'operation-not-allowed' || 'unauthorized-domain' =>
        'Google sign-in is not configured for Gmail permission on this domain.',
      _ => 'Could not get Gmail permission. Try linking Gmail again.',
    };
  }

  /// Builds an RFC 2822 message and returns it base64url-encoded, the form
  /// the Gmail `raw` field expects.
  ///
  /// The body is always sent as a `multipart/alternative` (plain text + HTML)
  /// so Gmail renders a properly formatted message — paragraphs and line
  /// breaks survive — while text-only clients still get a readable copy. When
  /// there are attachments, that alternative is nested inside a
  /// `multipart/mixed` alongside the files. Every part is base64-encoded so
  /// UTF-8 bodies and binary PDFs survive transport.
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
    final altBoundary = _boundary('alt');
    if (attachments.isEmpty) {
      message
        ..write(headers)
        ..write(
          'Content-Type: multipart/alternative; boundary="$altBoundary"$crlf',
        )
        ..write(crlf)
        ..write(_alternativeBody(body, altBoundary));
    } else {
      final mixedBoundary = _boundary('mixed');
      message
        ..write(headers)
        ..write('Content-Type: multipart/mixed; boundary="$mixedBoundary"$crlf')
        ..write(crlf)
        ..write('--$mixedBoundary$crlf')
        ..write(
          'Content-Type: multipart/alternative; boundary="$altBoundary"$crlf',
        )
        ..write(crlf)
        ..write(_alternativeBody(body, altBoundary))
        ..write(crlf);
      for (final att in attachments) {
        final name = _encodeHeaderValue(att.filename);
        message
          ..write('--$mixedBoundary$crlf')
          ..write('Content-Type: ${att.mimeType}; name="$name"$crlf')
          ..write('Content-Transfer-Encoding: base64$crlf')
          ..write('Content-Disposition: attachment; filename="$name"$crlf')
          ..write(crlf)
          ..write(_chunk(base64.encode(att.bytes)))
          ..write(crlf);
      }
      message.write('--$mixedBoundary--');
    }

    return base64Url.encode(utf8.encode(message.toString()));
  }

  /// A `multipart/alternative` section carrying the message as both plain text
  /// and HTML. Returns the section's parts plus its closing delimiter — the
  /// caller writes the enclosing `Content-Type: multipart/alternative` header.
  String _alternativeBody(String body, String boundary) {
    const crlf = '\r\n';
    return (StringBuffer()
          ..write('--$boundary$crlf')
          ..write('Content-Type: text/plain; charset="UTF-8"$crlf')
          ..write('Content-Transfer-Encoding: base64$crlf')
          ..write(crlf)
          ..write(_chunk(base64.encode(utf8.encode(body))))
          ..write(crlf)
          ..write('--$boundary$crlf')
          ..write('Content-Type: text/html; charset="UTF-8"$crlf')
          ..write('Content-Transfer-Encoding: base64$crlf')
          ..write(crlf)
          ..write(_chunk(base64.encode(utf8.encode(_bodyToHtml(body)))))
          ..write(crlf)
          ..write('--$boundary--$crlf'))
        .toString();
  }

  /// A unique MIME boundary. The [tag] keeps the mixed/alternative boundaries
  /// distinct even when minted in the same microsecond.
  String _boundary(String tag) =>
      'syncra_${tag}_${DateTime.now().microsecondsSinceEpoch}';

  /// Renders a plain-text body as email-safe HTML so it reads like a normal
  /// formatted Gmail message: blank lines become paragraphs, single newlines
  /// become `<br>`. All text is HTML-escaped first.
  String _bodyToHtml(String body) {
    final paragraphs = body
        .replaceAll('\r\n', '\n')
        .trim()
        .split(RegExp(r'\n{2,}'));
    final blocks = paragraphs
        .map(
          (p) =>
              '<p style="margin:0 0 12px;">${_escapeHtml(p).replaceAll('\n', '<br>')}</p>',
        )
        .join();
    return '<!DOCTYPE html><html><body style="font-family:-apple-system,'
        'Segoe UI,Roboto,Helvetica,Arial,sans-serif;font-size:14px;'
        'line-height:1.5;color:#1a1a1a;">$blocks</body></html>';
  }

  /// Escapes the five characters that would otherwise be parsed as HTML.
  String _escapeHtml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

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
      final end = (i + width < base64Text.length)
          ? i + width
          : base64Text.length;
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
        return 'Gmail request failed: ${error['message']}';
      }
    } catch (_) {
      // Fall through to the generic message.
    }
    return 'Gmail request failed (HTTP $status).';
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
