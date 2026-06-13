import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
    final key = _normalizeDomain(domain);
    if (key == null) return null;
    try {
      final snap = await _paths.companyContacts().doc(key).get();
      final email = (snap.data()?['email'] as String?)?.trim();
      return (email != null && email.isNotEmpty) ? email : null;
    } catch (e) {
      debugPrint('CompanyContactsRepository.lookupEmail failed: $e');
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
    final key = _normalizeDomain(domain);
    final clean = email.trim();
    if (key == null || !_looksLikeEmail(clean)) return;
    try {
      await _paths.companyContacts().doc(key).set({
        'email': clean,
        'domain': key,
        if (company != null && company.trim().isNotEmpty)
          'company': company.trim(),
        'source': 'user_confirmed',
        if (uid != null && uid.isNotEmpty) 'confirmedBy': uid,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('CompanyContactsRepository.saveConfirmedEmail failed: $e');
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
}
