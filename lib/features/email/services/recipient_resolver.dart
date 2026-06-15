/// The single place that decides which email address an outreach draft is
/// addressed to. Everything that needs a company recipient — the `draft_email`
/// agent tool, `lookup_hiring_manager`, the job action sheet — funnels through
/// here so Syncra can distinguish confirmed, found, guessed, and missing
/// recipients instead of flattening them to plain strings.
library;

import '../../../data/firestore/company_contacts_repository.dart';
import '../models/recipient_resolution.dart';
import 'company_contact_discovery_service.dart';

const demoEmailOverrideEnabled = bool.fromEnvironment(
  'SYNCRA_DEMO_EMAIL_OVERRIDE_ENABLED',
);

const demoEmailOverride = String.fromEnvironment('SYNCRA_DEMO_EMAIL_OVERRIDE');

String? activeDemoRecipientEmail({
  bool enabled = demoEmailOverrideEnabled,
  String overrideEmail = demoEmailOverride,
}) {
  final email = overrideEmail.trim();
  if (!enabled || !_looksLikeEmail(email)) return null;
  return email;
}

RecipientResolution? demoEmailOverrideResolution({
  bool enabled = demoEmailOverrideEnabled,
  String overrideEmail = demoEmailOverride,
  String? fallbackDomain,
}) {
  final email = activeDemoRecipientEmail(
    enabled: enabled,
    overrideEmail: overrideEmail,
  );
  if (email == null) return null;

  return RecipientResolution.confirmed(
    email: email,
    domain: _domainFromEmail(email) ?? fallbackDomain ?? 'demo.local',
    source: RecipientSource.demoOverride,
    reason: 'Controlled demo recipient override.',
    canAutoSend: true,
  );
}

bool isActiveDemoRecipient(String email) {
  final active = activeDemoRecipientEmail();
  return active != null && email.trim().toLowerCase() == active.toLowerCase();
}

bool _looksLikeEmail(String value) {
  final clean = value.trim();
  final at = clean.indexOf('@');
  return at > 0 && clean.indexOf('.', at) > at + 1 && !clean.contains(' ');
}

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

  final demoOverride = demoEmailOverrideResolution(fallbackDomain: domain);
  if (demoOverride != null) {
    return demoOverride;
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
  final demoOverride = activeDemoRecipientEmail();
  if (demoOverride != null) {
    return demoOverride;
  }
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
