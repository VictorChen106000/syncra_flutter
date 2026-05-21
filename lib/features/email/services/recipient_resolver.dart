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
/// ## Upgrade path — Hunter.io (option 3)
/// To return real verified addresses, add an async lookup *without* touching
/// any caller:
///   1. Add a `HunterService` (mirror `JSearchService`) reading its own
///      `HUNTER_API_KEY` — unrelated to the Anthropic/Claude key.
///   2. Add an async `resolveRecipientAsync(company, {website})` here that
///      tries Hunter first and falls back to [resolveRecipient] below.
///   3. Have callers `await` the async variant. The editable "To" field in the
///      review sheet stays as the human safety net either way.
library;

/// Best-effort recipient address for [company].
///
/// When the employer's real [website] is known (e.g. JSearch's
/// `employer_website`), its domain is used — a far better guess than slugging
/// the company name. Otherwise the name is slugged into a `.com` domain.
///
/// This is never guaranteed to be a live inbox; it only pre-fills the
/// editable "To" field so the user has a sensible default to correct.
String resolveRecipient(String company, {String? website}) {
  final domain = _domainFor(company, website);
  return 'careers@$domain';
}

/// Resolves the bare domain — the part Hunter.io would also key off of.
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
