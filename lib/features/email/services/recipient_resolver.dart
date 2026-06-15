/// The single place that decides which email address an outreach draft is
/// addressed to. Everything that needs a company recipient — the `draft_email`
/// agent tool, `lookup_hiring_manager`, the job action sheet — funnels through
/// here so the strategy can be swapped in one spot.
///
/// Today it is a deterministic *guess*: `careers@{domain}`. The job data
/// (JSearch) carries no real contact email, so this is a best-effort starting
/// point that the user is always expected to verify in the review sheet before
/// a draft is created.
///
/// ## How the recipient is resolved
/// [resolveRecipientAsync] tries, in order: an optional demo override, a
/// contact previously confirmed in the shared Firestore `company_contacts/`
/// directory (which can also be seeded before a demo so a known company
/// resolves to a real inbox we control — real delivery, no bounce), and finally
/// a deterministic `careers@{domain}` guess built from the company's real
/// website domain. Every step degrades to the next on failure, and the editable
/// "To" field in the review sheet stays as the human safety net.
library;

import '../../../data/firestore/company_contacts_repository.dart';

/// DEMO OVERRIDE — when non-empty, **every** outreach recipient is forced to
/// this address. It short-circuits the contacts lookup and the `careers@` guess
/// so live sends during a demo always reach a real inbox we control and never
/// bounce on a made-up company address.
///
/// Set back to `''` to restore normal `careers@` / learned-contact resolution
/// for production.
///
/// Off by default — every recipient is resolved dynamically per company
/// (confirmed Firestore contact → `careers@{domain}` guess) so the demo isn't
/// hardcoded to one inbox. Set a non-empty address only to force a safe
/// catch-all during a live send.
const String demoRecipientOverride = '';

/// Recipient address for [company], preferring a **real** address learned from
/// a previous confirmed send/draft over the `careers@{domain}` guess.
///
/// This is the Flutter + Firebase answer to "find the real receiver": it reads
/// the shared [CompanyContactsRepository] directory (keyed by company domain).
/// When a confirmed contact exists it is returned; otherwise it falls back to
/// [resolveRecipient]. Reads never throw — a Firestore hiccup just yields the
/// guess. Pass [contacts] to inject a fake in tests.
Future<String> resolveRecipientAsync(
  String company, {
  String? website,
  CompanyContactsRepository? contacts,
}) async {
  if (demoRecipientOverride.isNotEmpty) return demoRecipientOverride;

  final domain = recipientDomain(company, website: website);

  // 1. A real address confirmed for this company wins. The shared
  //    company_contacts/ directory can be seeded before a demo so a known
  //    company resolves to an inbox we control (real delivery, no bounce).
  final repo = contacts ?? CompanyContactsRepository();
  final saved = await repo.lookupEmail(domain);
  if (saved != null && saved.isNotEmpty) return saved;

  // 2. Deterministic careers@{domain} guess — always returns something.
  return resolveRecipient(company, website: website);
}

/// The bare company domain an outreach draft is keyed by — the same value the
/// contacts directory and the `careers@` guess are built from. Exposed so the
/// review sheet can save a confirmed address under the right key.
String recipientDomain(String company, {String? website}) =>
    _domainFor(company, website);

/// Best-effort recipient address for [company].
///
/// When the employer's real [website] is known (e.g. JSearch's
/// `employer_website`), its domain is used — a far better guess than slugging
/// the company name. Otherwise the name is slugged into a `.com` domain.
///
/// This is never guaranteed to be a live inbox; it only pre-fills the
/// editable "To" field so the user has a sensible default to correct.
String resolveRecipient(String company, {String? website}) {
  if (demoRecipientOverride.isNotEmpty) return demoRecipientOverride;
  final domain = _domainFor(company, website);
  return 'careers@$domain';
}

/// Resolves the bare company domain used for the contacts lookup and guess.
String _domainFor(String company, String? website) {
  final fromWebsite = _domainFromWebsite(website);
  if (fromWebsite != null) return fromWebsite;

  final slug =
      company.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').trim();
  return slug.isEmpty ? 'example.com' : '$slug.com';
}

/// Extracts a clean host from a website URL, stripping scheme, `www.`, paths,
/// and ports. Returns null when [website] is empty or unparseable.
String? _domainFromWebsite(String? website) {
  final raw = website?.trim();
  if (raw == null || raw.isEmpty) return null;

  // Uri.parse needs a scheme to populate `host`; add one if it's missing.
  final withScheme =
      raw.contains('://') ? raw : 'https://$raw';
  final host = Uri.tryParse(withScheme)?.host.toLowerCase();
  if (host == null || host.isEmpty) return null;

  final cleaned = host.startsWith('www.') ? host.substring(4) : host;
  return cleaned.isEmpty ? null : cleaned;
}
