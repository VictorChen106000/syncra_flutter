import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../data/firestore/applications_repository.dart';
import 'gmail_service.dart';

/// Outcome of a successful confirmed send.
class EmailSendResult {
  const EmailSendResult({required this.messageId, required this.sentAt});

  final String messageId;
  final DateTime sentAt;
}

/// The bridge between the email review modal and the `send_email` agent tool.
///
/// It enforces the human-in-the-loop rule from api-contract §1: `send_email`
/// must NEVER fire without an explicit user tap. The review modal is the only
/// code path allowed to [mintConfirmationToken]; [sendConfirmed] rejects any
/// call whose token it did not mint. Claude's autonomous `send_email` calls
/// carry no token, so they are refused before a single byte leaves the device.
///
/// A token is one-shot — it is consumed on first use and cannot authorize a
/// second send, so a replayed tool call can't piggy-back on an old approval.
///
/// Implemented as a singleton because the token gate has to be shared between
/// the modal (which mints) and the tool executor (which validates), and
/// `registerBuiltinTools` has no Riverpod `Ref` to inject a shared instance.
class EmailSendService {
  EmailSendService._();

  /// The shared instance used by both the review modal and the agent tool.
  static final EmailSendService instance = EmailSendService._();

  GmailService? _gmail;
  ApplicationsRepository? _applications;

  GmailService get _gmailService => _gmail ??= GmailService();
  ApplicationsRepository get _applicationsRepo =>
      _applications ??= ApplicationsRepository();

  /// Overrides the collaborators — for tests only.
  @visibleForTesting
  void debugOverrideDependencies({
    GmailService? gmail,
    ApplicationsRepository? applications,
  }) {
    _gmail = gmail;
    _applications = applications;
  }

  final Random _random = Random.secure();

  /// Unused one-shot confirmation tokens. A token is added by
  /// [mintConfirmationToken] and removed the first time it is presented to
  /// [sendConfirmed].
  final Set<String> _pendingTokens = {};

  /// Mints a one-shot confirmation token. Called by the email review modal
  /// immediately before it sends — the token authorizes exactly one
  /// [sendConfirmed] call. Nothing else in the app should call this.
  String mintConfirmationToken() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final token =
        bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    _pendingTokens.add(token);
    return token;
  }

  /// Whether [token] is a live, unused confirmation token. The `send_email`
  /// executor calls this to tell a user-driven send from an autonomous one.
  bool isValidToken(String? token) =>
      token != null && token.isNotEmpty && _pendingTokens.contains(token);

  /// Sends an email — but only when [confirmationToken] was minted by
  /// [mintConfirmationToken] and not yet spent. On success, stamps `sent_at`
  /// and `sent_email_id` on the application doc when [uid] and [applicationId]
  /// are supplied (api-contract §3).
  ///
  /// Throws [EmailNotConfirmedException] if the token is missing or invalid,
  /// and [GmailException] if the Gmail API rejects the send.
  Future<EmailSendResult> sendConfirmed({
    required String? confirmationToken,
    required String to,
    required String subject,
    required String body,
    String? uid,
    String? applicationId,
    List<EmailAttachment> attachments = const [],
  }) async {
    if (!isValidToken(confirmationToken)) {
      throw const EmailNotConfirmedException();
    }
    // Burn the token before sending: even if the send throws, this approval
    // is spent, so any retry must come from a fresh user tap.
    _pendingTokens.remove(confirmationToken);

    final messageId = await _gmailService.send(
      to: to,
      subject: subject,
      body: body,
      attachments: attachments,
    );
    final sentAt = DateTime.now();

    // Tracker stamp is best-effort — a delivered email must not look failed
    // just because the Firestore write hiccuped.
    if (uid != null &&
        uid.isNotEmpty &&
        applicationId != null &&
        applicationId.isNotEmpty) {
      try {
        await _applicationsRepo.markSent(
          uid,
          applicationId,
          sentEmailId: messageId,
        );
      } catch (e) {
        debugPrint('EmailSendService: markSent failed (ignored): $e');
      }
    }

    return EmailSendResult(messageId: messageId, sentAt: sentAt);
  }
}

/// Raised when `send_email` is called without a valid confirmation token —
/// i.e. someone tried to send outside the review modal.
class EmailNotConfirmedException implements Exception {
  const EmailNotConfirmedException();

  @override
  String toString() =>
      'EmailNotConfirmedException: send_email needs a confirmation token '
      'minted by the email review modal.';
}
