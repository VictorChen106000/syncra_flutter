# Application Link First Flow + Job Action Modal — Implementation Plan (codebase-grounded)

> This plan was rewritten **after reading the actual Syncra source** so every
> file path, field name, and "current behaviour" note below reflects what is on
> `main` today. Where the original product brief assumed something that isn't
> true in this codebase, the discrepancy is called out inline as **REALITY**.

---

## Context (verified against current `main`)

- JSearch reads a combined `sourceUrl` and uses it **only** to mint a
  deterministic job ID:
  `lib/data/services/jsearch_service.dart:194` —
  `((raw['job_apply_link'] ?? raw['job_google_link']) as String?)?.trim() ?? ''`.
- The `Job` model (`lib/data/models/job.dart`) preserves `employerWebsite`
  (default `''`) but **not** `applyLink`, `googleJobLink`, `sourceUrl`,
  `publisher`, or `providerSource`.
- The `jobs/` upsert (`jsearch_service.dart:284`) writes
  `title, company, location, salary, description, employer_website, source,
  discovered_at` — no apply/source links.
- **REALITY — `url_launcher` is NOT a dependency.** `pubspec.yaml` has
  `share_plus ^12.0.2`, `http ^1.5.0`, `crypto ^3.0.6`. There is **no**
  `lib/core/utils/url_opener.dart`. It must be added.
- **REALITY — the chat snapshot codec is already covered.**
  `lib/features/agent_chat/services/chat_snapshot_codec.dart` encodes jobs with
  `job.toJson()` (line 74) and decodes with `Job.fromJson` (line 470). Fixing
  the `Job` model automatically carries the new fields through chat history —
  **no codec edit is needed** beyond a regression test.
- **REALITY — the pipeline drops most job fields.**
  `PipelineRepository.createCard` (`lib/data/firestore/pipeline_repository.dart:147`)
  writes a nested `job` map with only `id, title, company, location, salary` —
  it doesn't even persist `employerWebsite` today. This is the biggest gap.
- **REALITY — "handled/history job card" is not one widget.** Handled jobs are
  *removed* from the chat rail (`agent_block_views.dart:94`, `inactiveIds`).
  Post-action history lives in two places:
  - **Applications** tab → `TrackedApplication` rows → `ApplicationDetailSheet`.
  - **Jobs** page pipeline cards (`lib/features/jobs/presentation/jobs_page.dart`).
  See **Phase 3** for where the icons + modal actually attach.
- **REALITY — the "hardcoded/demo email" is real and findable.**
  `lib/features/email/services/recipient_resolver.dart:21` defines
  `demoRecipientOverride = 'pegatron.inc@gmail.com'`. `resolveRecipientAsync`
  already accepts an `applyLink` argument (line 32) and can derive a domain from
  it.
- **REALITY — no per-job chat thread.** Chat is a single transcript
  (`agentChatProvider`). The route is `RouteNames.agentChat` (`/agent-chat`),
  which only understands a `?focus=1` query param (`app_router.dart:138`). There
  is no prompt-seeding API yet — Row 4 must either add one to
  `agent_chat_notifier.dart` or settle for navigating + autofocusing.

This update shifts the product from **email-first** to
**application-link-first**: after Syncra handles a job, the user should always
have a real link to open, with email as a secondary path.

---

## Non-Negotiable Rules (unchanged from brief)

1. Do not remove existing resume tailoring, draft email, pipeline, or
   application-history behaviour.
2. Do not expose or commit API secrets. The RapidAPI/JSearch key (starts `9`,
   ends `f`) must never appear in source, tests, docs, or logs.
3. Do not call JSearch directly from Flutter with a real key. Keep the existing
   `SyncraProxy.jsearch` proxy flow.
4. Do not scrape application/ATS/job-board pages for emails. Opening those links
   for the user is fine; scraping them is not.
5. Email stays secondary. With no verified recipient, show the email row as
   review/fallback/demo only.
6. Keep backward compatibility: old Firestore docs missing the new fields must
   still load. Every new field defaults to `''`.

---

## Target Data Model

`lib/data/models/job.dart` — add five fields, all defaulting to `''`:

```dart
final String applyLink;      // raw['job_apply_link'] only
final String googleJobLink;  // raw['job_google_link'] only
final String sourceUrl;      // applyLink if non-empty, else googleJobLink
final String publisher;      // raw['job_publisher'] when present
final String providerSource; // 'jsearch' for JSearch jobs, else ''
```

Keep `employerWebsite` as-is. Wire all five into the constructor, `fromJson`
(reading `apply_link`, `google_job_link`, `source_url`, `publisher`,
`provider_source` with `?? ''`), and `toJson`.

| Field | Source | UI use |
|---|---|---|
| `applyLink` | `job_apply_link` | Primary "Open application" |
| `googleJobLink` | `job_google_link` | "View Google listing" |
| `sourceUrl` | `applyLink` else `googleJobLink` | Provenance / fallback open |
| `publisher` | `job_publisher` | Source label |
| `providerSource` | const `'jsearch'` | Provenance label |
| `employerWebsite` | `employer_website` | Company website |

---

## Phase 1 — Preserve JSearch provenance fields

**File:** `lib/data/services/jsearch_service.dart`

In `_jsearchToJob` (line ~191) replace the combined extraction with explicit
fields:

```dart
final applyLink = (raw['job_apply_link'] as String?)?.trim() ?? '';
final googleJobLink = (raw['job_google_link'] as String?)?.trim() ?? '';
final sourceUrl = applyLink.isNotEmpty ? applyLink : googleJobLink;
final publisher = (raw['job_publisher'] as String?)?.trim() ?? '';
final employerWebsite = (raw['employer_website'] as String?)?.trim() ?? '';
```

- Keep the existing reject rule (`title`/`company`/`sourceUrl` empty → null) and
  the deterministic `_jobIdFor(title, company, sourceUrl)`.
- Pass `applyLink`, `googleJobLink`, `sourceUrl`, `publisher`,
  `providerSource: 'jsearch'`, and `employerWebsite` into the returned `Job`.

In `_upsert` (line ~284) add to the batch payload (do **not** remove existing
keys):

```dart
'apply_link': job.applyLink,
'google_job_link': job.googleJobLink,
'source_url': job.sourceUrl,
'publisher': job.publisher,
'provider_source': job.providerSource,
// 'employer_website' and 'source': 'jsearch' already present
```

---

## Phase 2 — Carry fields through every storage layer

1. **`lib/data/models/job.dart`** — fields + `fromJson`/`toJson` (above).
   This automatically fixes the **chat snapshot codec** (it round-trips through
   `Job.toJson`/`fromJson`). No codec change required.
2. **`lib/data/firestore/jobs_repository.dart`** — both `_fromDoc` and
   `_fromDocSnap` build `Job` by hand; add `applyLink`, `googleJobLink`,
   `sourceUrl`, `publisher`, `providerSource` from `m['apply_link']` etc.
   (`?? ''`).
3. **`lib/data/firestore/pipeline_repository.dart`** —
   - `createCard` nested `job` map (line ~147): add `apply_link`,
     `google_job_link`, `source_url`, `publisher`, `provider_source`, and
     `employer_website` (currently missing entirely).
   - `_fromDoc` (line ~211): restore those from `jobMap[...]`.
4. **`lib/data/firestore/applications_repository.dart`** —
   - `_jobToMap` (line ~161): add the five fields + `employer_website`.
   - `_jobFromMap` (line ~146): restore them.
5. **Chat snapshot** — add a round-trip regression test only (no code change).

---

## Phase 3 — Action icons on handled/history cards

**REALITY decision:** the icons attach where handled jobs are actually visible.
Recommended primary target is the **Applications** surface (the
`TrackedApplication` rows that open `ApplicationDetailSheet`), since that's the
post-action history the brief describes. Optionally also add them to the chat
`_JobMatchCard` (`agent_block_views.dart`) for live results.

Three compact icons, lower-right, matching the dark/rounded/lime styling
(`context.brand`):

| Icon | Active when | Tap |
|---|---|---|
| Link (`Icons.link_rounded`) | `applyLink` / `sourceUrl` / `googleJobLink` / `employerWebsite` non-empty | Opens modal Row 1 |
| Resume (`Icons.description_rounded`) | `TrackedApplication.resumeId != null` (or a tailored resume exists) | Opens modal Row 3 |
| Email (`Icons.mail_outline_rounded`) | a draft/recipient exists (`sentEmailId`/phase) | Opens modal Row 2 |

Muted = `brand.textSoft`; active = `brand.ink`. Keep them small (≈18px) so they
read as chips, not buttons.

---

## Phase 4 — Bottom modal with four rows

Build a new sheet (e.g. `lib/features/applications/presentation/widgets/job_links_sheet.dart`)
opened on card tap, OR extend `ApplicationDetailSheet`. Single column, four rows.
Reuse the existing sheet scaffold pattern (`showModalBottomSheet`,
`useRootNavigator: true`, `isScrollControlled: true`, `brand.bg`, top grab
handle) from `ApplicationDetailSheet`.

- **Row 1 — Application links.** Priority: `applyLink` → primary
  **Open application**; `googleJobLink` → **View Google listing**;
  `sourceUrl` (if different) → **View source**; `employerWebsite` →
  **Company website**. Small labels: `Publisher: <publisher>`,
  `Source: JSearch` when present.
- **Row 2 — Email (secondary).** Show the resolved recipient (today this is
  `demoRecipientOverride` → `pegatron.inc@gmail.com`; surface it as a demo
  recipient). If none: "No verified recipient yet. Email is optional." Offer the
  existing draft action (`_draftEmail` flow in `job_action_sheet.dart` /
  `EmailReviewPage`). Never the primary action.
- **Row 3 — Resume.** If a tailored/saved resume is linked (`resumeId`), show
  "Tailored resume ready" + open/preview via the existing resume preview route.
  Else "No tailored resume saved yet" + a Tailor action only if the existing
  flow supports it (don't build a new pipeline).
- **Row 4 — Chatbot prompt bar.** Rounded dark input + lime arrow
  (mirror the `InputRequestView` text field / `_NoteComposer` styling). Tapping
  navigates to `RouteNames.agentChat`. **REALITY:** there's no per-job thread or
  prompt-seed API. Either (a) add a seed method to `agent_chat_notifier.dart`
  and call it before `context.go('/agent-chat?focus=1')`, or (b) ship a safe
  navigate-and-focus first. Do **not** auto-send email from this row.

Suggested seed prompt:

```text
Continue helping me with this application:
Role: <job.title>
Company: <job.company>
Location: <job.location>
Application link: <job.applyLink or job.sourceUrl>
Publisher: <job.publisher>
Please help me decide next step, improve my resume, or prepare outreach.
```

---

## Phase 5 — Application link as the primary success result

Update copy so the visible outcome leads with the link, e.g.
`Application link ready · Draft ready for review`, or when no email:
`Application link ready · Email optional`. The agent flow should treat "a direct
apply link exists" as a useful completed result rather than blocking on email
discovery.

---

## Phase 6 — URL opening (new dependency)

1. Add `url_launcher` to `pubspec.yaml` (it is **not** currently present) and run
   `flutter pub get`.
2. Create `lib/core/utils/url_opener.dart`: validate the URL
   (`Uri.tryParse`, require an http/https scheme), `launchUrl(..., mode:
   LaunchMode.externalApplication)`, and on failure return false so callers can
   show a snackbar. Never throw into the UI.
3. Platform config: Android `queries`/`<intent>` for `https` in
   `AndroidManifest.xml` and iOS `LSApplicationQueriesSchemes` only if needed.

---

## Phase 7 — JSearch link verification (CI-safe)

- **Option A (mandatory):** unit test mocking the JSearch HTTP response (inject a
  mock `http.Client` into `JSearchService`) asserting `job_apply_link →
  applyLink`, `job_google_link → googleJobLink`, `sourceUrl` prefers apply then
  falls back to google, `job_publisher → publisher`, `providerSource == 'jsearch'`,
  `employer_website → employerWebsite`.
- **Option B (optional, local only):** a runbook note. Read the key from
  `$env:RAPIDAPI_KEY`, hit the existing proxy, print only safe fields. Never
  print or commit the key.

---

## Phase 8 — Tests

- **Model** (`test/job_model_test.dart`): `toJson`/`fromJson` round-trip all five
  new fields; missing keys default to `''`.
- **JSearch** (`test/jsearch_service_test.dart`): mocked-response mapping
  assertions from Phase 7A.
- **Serialization** (extend existing `test/pipeline_repository_test.dart`; add
  jobs/applications coverage): pipeline + applications nested job maps preserve
  the fields; chat snapshot round-trip preserves them.
- **UI** (`test/application_link_flow_ui_test.dart`): icons render and link icon
  is active when `applyLink`/`sourceUrl` exists; tapping a history card opens the
  modal; modal shows four rows; Row 1 shows "Open application" only when
  `applyLink` exists; "View Google listing" only when `googleJobLink` exists;
  Row 4 navigates to chat / seeds the contextual prompt.

---

## Commands

```powershell
# flutter/dart are not on PATH — SDK lives at C:\Users\User\sdk123\flutter
$flutter = "C:\Users\User\sdk123\flutter\bin\flutter.bat"
& $flutter pub get          # after adding url_launcher
& $flutter test
& $flutter analyze
```

```powershell
git add lib test pubspec.yaml pubspec.lock docs codex_application_link_first_flow_plan.md
git commit -m "Add application link first flow"
```

---

## Manual QA scenarios

1. **Direct apply link** — search returns roles; history card link icon active;
   modal Row 1 → "Open application" opens `job_apply_link`.
2. **Google-only link** — `applyLink` empty, `googleJobLink` preserved; modal
   shows "View Google listing", not "Open application"; provenance still shown.
3. **Email unavailable** — link still gives a result; Row 2 reads demo/optional;
   flow not blocked.
4. **Tailored resume exists** — resume icon active; Row 3 "Tailored resume
   ready" opens preview.
5. **Chat continuation** — Row 4 opens chat with job context; no email
   auto-sent.
