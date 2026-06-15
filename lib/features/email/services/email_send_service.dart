import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../../data/firestore/applications_repository.dart';
import '../../../data/firestore/company_contacts_repository.dart';
import '../models/recipient_resolution.dart';
import 'gmail_service.dart';
import 'recipient_resolver.dart';

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
  CompanyContactsRepository? _contacts;

  GmailService get _gmailService => _gmail ??= GmailService();
  ApplicationsRepository get _applicationsRepo =>
      _applications ??= ApplicationsRepository();
  CompanyContactsRepository get _contactsRepo =>
      _contacts ??= CompanyContactsRepository();

  /// Overrides the collaborators — for tests only.
  @visibleForTesting
  void debugOverrideDependencies({
    GmailService? gmail,
    ApplicationsRepository? applications,
    CompanyContactsRepository? contacts,
  }) {
    _gmail = gmail;
    _applications = applications;
    _contacts = contacts;
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
    final token = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
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
    String? contactDomain,
    String? company,
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

    // A confirmed send is the strongest signal that [to] is the right address
    // for this company — record it so the next draft pre-fills the real one.
    await _learnRecipient(
      to: to,
      contactDomain: contactDomain,
      company: company,
      uid: uid,
    );

    return EmailSendResult(messageId: messageId, sentAt: sentAt);
  }

  /// Sends an agent-drafted outreach email **without** a per-email tap, for
  /// the **Autopilot** autonomy level.
  ///
  /// This is the *only* place outside the review sheet allowed to mint a
  /// confirmation token. It is justified because the caller (the draft card)
  /// has already cleared the gates that together stand in for the per-email tap:
  ///   1. the user chose `AutonomyLevel.autopilot`,
  ///   2. the job passed the low-risk trust floor (`evaluateJobTrust`),
  ///   3. the recipient is a real address, and
  ///   4. the user let the on-card Undo window elapse without cancelling.
  /// The caller must enforce all of these before calling this — this method
  /// does not re-check them. Note this means the model can never send on its
  /// own (it cannot mint a token); only this app-controlled path can. Everything
  /// downstream (send, `markSent`, recipient learning) is shared with
  /// [sendConfirmed].
  Future<EmailSendResult> autoSend({
    required String to,
    required String subject,
    required String body,
    required RecipientResolution recipientResolution,
    String? uid,
    String? applicationId,
    List<EmailAttachment> attachments = const [],
    String? contactDomain,
    String? company,
  }) {
    if (!recipientResolution.isAutoSendEligible) {
      throw StateError(
        'Auto-send requires a confirmed or high-confidence recipient.',
      );
    }
    return sendConfirmed(
      confirmationToken: mintConfirmationToken(),
      to: to,
      subject: subject,
      body: body,
      uid: uid,
      applicationId: applicationId,
      attachments: attachments,
      contactDomain: contactDomain,
      company: company,
    );
  }

  /// Creates a draft in the user's Gmail Drafts folder. Returns the draft id.
  ///
  /// Unlike [sendConfirmed] this needs no confirmation token: a draft is never
  /// delivered, so the human-in-the-loop rule (api-contract §1) is satisfied
  /// by Gmail itself — the user still has to open the draft and hit send.
  /// Drafting is therefore safe for the agent to surface directly.
  Future<String> createDraft({
    required String to,
    required String subject,
    required String body,
    List<EmailAttachment> attachments = const [],
    String? contactDomain,
    String? company,
    String? uid,
    bool learnRecipient = true,
  }) async {
    final draftId = await _gmailService.createDraft(
      to: to,
      subject: subject,
      body: body,
      attachments: attachments,
    );

    if (learnRecipient) {
      await _learnRecipient(
        to: to,
        contactDomain: contactDomain,
        company: company,
        uid: uid,
      );
    }

    return draftId;
  }

  /// Records the confirmed recipient [to] in the shared contacts directory.
  /// Best-effort and never throws: a learning hiccup must not fail the send or
  /// draft the user just completed. When [contactDomain] is omitted, the domain
  /// is taken from the recipient address itself.
  Future<void> _learnRecipient({
    required String to,
    String? contactDomain,
    String? company,
    String? uid,
  }) async {
    // Don't learn the demo override address — it isn't a real company contact,
    // and saving it would resurface as a bogus "learned" recipient later.
    if (demoRecipientOverride.isNotEmpty &&
        to.trim() == demoRecipientOverride) {
      return;
    }
    // Wrap everything — including building the repository — so a missing
    // Firebase (e.g. in unit tests) or any write failure can never break the
    // send/draft the user just completed.
    try {
      final domain = (contactDomain != null && contactDomain.trim().isNotEmpty)
          ? contactDomain.trim()
          : _domainFromEmail(to);
      if (domain == null) return;
      await _contactsRepo.saveConfirmedEmail(
        domain: domain,
        email: to,
        company: company,
        uid: uid,
      );
    } catch (e) {
      debugPrint('EmailSendService: learnRecipient failed (ignored): $e');
    }
  }

  /// The domain part of an email address, lower-cased, or `null` if [email]
  /// has no usable `@host`.
  String? _domainFromEmail(String email) {
    final at = email.lastIndexOf('@');
    if (at < 0) return null;
    final domain = email.substring(at + 1).trim().toLowerCase();
    return domain.isEmpty ? null : domain;
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
