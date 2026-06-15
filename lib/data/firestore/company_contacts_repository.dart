import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../features/email/models/recipient_resolution.dart';
import 'firestore_paths.dart';

/// Shared, app-wide directory of confirmed outreach recipient addresses, keyed
/// by company **domain** (e.g. `acme.com`).
///
/// This is how Syncra finds the *real* receiver address without an external
/// email-finding service: instead of guessing `careers@{domain}` every time,
/// it remembers the address a user actually confirmed in the email review
/// sheet. The next person drafting outreach to the same company gets that real
/// address pre-filled.
///
/// Top-level collection — like `jobs/` — so a learned contact is reused across
/// users. See `firestore.rules` (`match /company_contacts/{domain}`): any
/// signed-in user can read and write, matching the class-demo posture.
class CompanyContactsRepository {
  CompanyContactsRepository({FirebaseFirestore? db})
    : _paths = FirestorePaths(db ?? FirebaseFirestore.instance);

  final FirestorePaths _paths;

  /// The stored recipient email for [domain], or `null` when none is recorded
  /// yet. Never throws — on a read failure it returns `null` so the caller
  /// falls back to the `careers@{domain}` guess.
  Future<String?> lookupEmail(String domain) async {
    final resolution = await lookupResolution(domain);
    return resolution?.email;
  }

  /// The stored recipient metadata for [domain], or `null` when none is
  /// recorded yet. Existing docs that only contain `email` are treated as
  /// confirmed cache hits for backward compatibility.
  Future<RecipientResolution?> lookupResolution(String domain) async {
    final key = _normalizeDomain(domain);
    if (key == null) return null;
    try {
      final snap = await _paths.companyContacts().doc(key).get();
      final data = snap.data();
      if (data == null) return null;
      final email = (data['email'] as String?)?.trim();
      if (email == null || email.isEmpty) return null;

      final confidence = _confidenceFrom(data['confidence']);
      final storedSource = _sourceFrom(data['source']);
      final sourceUrl = (data['sourceUrl'] as String?)?.trim();
      final reason = (data['reason'] as String?)?.trim();
      final autoSend =
          data['canAutoSend'] == true ||
          confidence == RecipientConfidence.confirmed ||
          confidence == RecipientConfidence.high;

      return RecipientResolution(
        email: email,
        domain: key,
        confidence: confidence,
        source: RecipientSource.confirmedCache,
        label: 'Confirmed contact',
        sourceUrl: sourceUrl == null || sourceUrl.isEmpty ? null : sourceUrl,
        reason: reason == null || reason.isEmpty
            ? storedSource == RecipientSource.none
                  ? 'Existing confirmed contact'
                  : 'Existing confirmed contact from ${storedSource.name}'
            : reason,
        canAutoSend: autoSend,
        requiresUserConfirmation:
            confidence != RecipientConfidence.confirmed &&
            confidence != RecipientConfidence.high,
      );
    } catch (e) {
      debugPrint('CompanyContactsRepository.lookupResolution failed: $e');
      return null;
    }
  }

  /// Records [email] as the confirmed recipient for [domain]. Best-effort: a
  /// learning write must never break the send/draft the user just completed,
  /// so failures are swallowed. Skips obviously invalid input (empty domain or
  /// a value that is not an email) rather than polluting the directory.
  Future<void> saveConfirmedEmail({
    required String domain,
    required String email,
    String? company,
    String? uid,
  }) async {
    await saveConfirmedResolution(
      RecipientResolution.confirmed(
        email: email,
        domain: domain,
        reason: 'User confirmed this contact from the email review flow.',
      ),
      company: company,
      uid: uid,
    );
  }

  /// Records [resolution] as a confirmed recipient for its domain. Best-effort:
  /// a learning write must never break the send/draft the user just completed.
  Future<void> saveConfirmedResolution(
    RecipientResolution resolution, {
    String? company,
    String? uid,
  }) async {
    final domain = resolution.domain.isNotEmpty
        ? resolution.domain
        : _domainFromEmail(resolution.email);
    final key = _normalizeDomain(domain);
    final clean = resolution.email.trim();
    if (key == null || !_looksLikeEmail(clean)) return;
    try {
      await _paths.companyContacts().doc(key).set({
        'email': clean,
        'domain': key,
        if (company != null && company.trim().isNotEmpty)
          'company': company.trim(),
        'source': resolution.source == RecipientSource.none
            ? RecipientSource.confirmedCache.name
            : resolution.source.name,
        'confidence': RecipientConfidence.confirmed.name,
        if (resolution.sourceUrl != null &&
            resolution.sourceUrl!.trim().isNotEmpty)
          'sourceUrl': resolution.sourceUrl!.trim(),
        'reason': resolution.reason.trim().isEmpty
            ? 'User confirmed this contact from the email review flow.'
            : resolution.reason.trim(),
        if (uid != null && uid.isNotEmpty) 'confirmedBy': uid,
        'confirmedCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastVerifiedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint(
        'CompanyContactsRepository.saveConfirmedResolution failed: $e',
      );
    }
  }

  /// Records a rejection signal for [domain] without deleting the current
  /// contact. The count helps a future backend avoid repeatedly surfacing a bad
  /// public inbox.
  Future<void> markRejected(String domain) async {
    final key = _normalizeDomain(domain);
    if (key == null) return;
    try {
      await _paths.companyContacts().doc(key).set({
        'domain': key,
        'rejectedCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('CompanyContactsRepository.markRejected failed: $e');
    }
  }

  /// Lower-cases and trims [domain]; returns `null` when it is empty.
  String? _normalizeDomain(String domain) {
    final d = domain.trim().toLowerCase();
    return d.isEmpty ? null : d;
  }

  /// A light sanity check — enough to reject blanks and non-addresses without
  /// pretending to fully validate RFC 5322.
  bool _looksLikeEmail(String value) {
    final at = value.indexOf('@');
    return at > 0 && value.indexOf('.', at) > at + 1;
  }

  String _domainFromEmail(String email) {
    final at = email.lastIndexOf('@');
    if (at < 0 || at == email.length - 1) return '';
    return email.substring(at + 1).trim().toLowerCase();
  }

  RecipientConfidence _confidenceFrom(Object? raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty) return RecipientConfidence.confirmed;
    for (final confidence in RecipientConfidence.values) {
      if (confidence.name == value) return confidence;
    }
    return RecipientConfidence.confirmed;
  }

  RecipientSource _sourceFrom(Object? raw) {
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty || value == 'user_confirmed') {
      return RecipientSource.confirmedCache;
    }
    for (final source in RecipientSource.values) {
      if (source.name == value) return source;
    }
    return RecipientSource.confirmedCache;
  }
}
