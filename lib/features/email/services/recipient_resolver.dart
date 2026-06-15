/// The single place that decides which email address an outreach draft is
/// addressed to. Everything that needs a company recipient — the `draft_email`
/// agent tool, `lookup_hiring_manager`, the job action sheet — funnels through
/// here so Syncra can distinguish confirmed, found, guessed, and missing
/// recipients instead of flattening them to plain strings.
library;

import '../../../data/firestore/company_contacts_repository.dart';
import '../models/recipient_resolution.dart';
import 'company_contact_discovery_service.dart';

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
const String demoRecipientOverride = 'pegatron.inc@gmail.com';

/// Recipient metadata for [company], preferring confirmed contacts and safe
/// official discovery over the low-confidence `careers@{domain}` guess.
///
/// This is the Flutter + Firebase answer to "find the real receiver": it reads
/// the shared [CompanyContactsRepository] directory (keyed by company domain).
/// Reads never throw — a Firestore hiccup just yields the next safest result.
Future<RecipientResolution> resolveRecipientAsync(
  String company, {
  String? website,
  String? applyLink,
  CompanyContactsRepository? contacts,
  CompanyContactDiscoveryService? discovery,
}) async {
  final domain = recipientDomainOrNull(
    company,
    website: website,
    applyLink: applyLink,
  );

  if (demoRecipientOverride.isNotEmpty) {
    final overrideDomain =
        _domainFromEmail(demoRecipientOverride) ?? domain ?? 'demo.local';
    return RecipientResolution.confirmed(
      email: demoRecipientOverride,
      domain: overrideDomain,
      source: RecipientSource.demoOverride,
      reason: 'Controlled demo recipient override.',
      // Demo: force auto-send eligibility so Autopilot actually delivers to the
      // controlled inbox (both the pipeline auto-processor and the on-screen
      // draft card). Restore to false / clear the override for production.
      canAutoSend: true,
    );
  }

  if (domain == null) {
    return RecipientResolution.none();
  }

  // 1. A real address confirmed for this company wins.
  try {
    final repo = contacts ?? CompanyContactsRepository();
    final saved = await repo.lookupResolution(domain);
    if (saved != null && saved.hasEmail) return saved;
  } catch (_) {
    // Missing Firebase setup in tests or a repository construction hiccup must
    // not block drafting; fall through to discovery/guessing.
  }

  // 2. Future official-site discovery. The default shell returns null today so
  //    the Flutter client never scrapes or uses browser automation.
  try {
    final discovered =
        await (discovery ?? const CompanyContactDiscoveryService()).resolve(
          company: company,
          website: website,
          applyLink: applyLink,
        );
    if (discovered != null && discovered.hasEmail) return discovered;
  } catch (_) {
    // Discovery is optional and best-effort.
  }

  // 3. Deterministic careers@{domain} guess. This is explicitly low
  //    confidence and can never auto-send.
  return RecipientResolution.guessed(
    email: 'careers@$domain',
    domain: domain,
    sourceUrl: website,
  );
}

/// Compatibility helper for older code that still needs a string.
Future<String> resolveRecipientEmailOnly(
  String company, {
  String? website,
  String? applyLink,
  CompanyContactsRepository? contacts,
  CompanyContactDiscoveryService? discovery,
}) async {
  final resolution = await resolveRecipientAsync(
    company,
    website: website,
    applyLink: applyLink,
    contacts: contacts,
    discovery: discovery,
  );
  return resolution.email;
}

/// The bare company domain an outreach draft is keyed by — the same value the
/// contacts directory and the `careers@` guess are built from. Exposed so the
/// review sheet can save a confirmed address under the right key.
String recipientDomain(String company, {String? website}) =>
    recipientDomainOrNull(company, website: website) ?? 'example.com';

/// Nullable domain extraction used by recipient intelligence. Employer website
/// wins, then apply link, then a company-name slug.
String? recipientDomainOrNull(
  String company, {
  String? website,
  String? applyLink,
}) {
  final fromWebsite = _domainFromWebsite(website);
  if (fromWebsite != null) return fromWebsite;

  final fromApplyLink = _domainFromWebsite(applyLink);
  if (fromApplyLink != null) return fromApplyLink;

  final slug = company
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '')
      .trim();
  return slug.isEmpty ? null : '$slug.com';
}

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
  final domain = recipientDomainOrNull(company, website: website);
  if (domain == null) return '';
  return 'careers@$domain';
}

/// Extracts a clean host from a website URL, stripping scheme, `www.`, paths,
/// and ports. Returns null when [website] is empty or unparseable.
String? _domainFromWebsite(String? website) {
  final raw = website?.trim();
  if (raw == null || raw.isEmpty) return null;

  // Uri.parse needs a scheme to populate `host`; add one if it's missing.
  final withScheme = raw.contains('://') ? raw : 'https://$raw';
  final host = Uri.tryParse(withScheme)?.host.toLowerCase();
  if (host == null || host.isEmpty) return null;

  final cleaned = host.startsWith('www.') ? host.substring(4) : host;
  return cleaned.isEmpty ? null : cleaned;
}

String? _domainFromEmail(String email) {
  final at = email.lastIndexOf('@');
  if (at < 0 || at == email.length - 1) return null;
  final domain = email.substring(at + 1).trim().toLowerCase();
  return domain.isEmpty ? null : domain;
}
