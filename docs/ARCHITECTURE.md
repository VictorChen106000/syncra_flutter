# Syncra — Architecture

How Syncra is wired. This is the **target contract**: if code disagrees with
this file, fix the code (or change this file by PR). Product context is in
[README.md](./README.md); current build status and ownership in
[STATUS.md](./STATUS.md).

## 0. Locked decisions

| Area | Decision |
| --- | --- |
| Platform | Flutter — iOS / Android / Web |
| Server | No non-Firebase backend. No Railway/FastAPI/custom Python server. Firebase Cloud Functions is deferred and not used in v1. |
| Auth | Firebase Auth — Google Sign-In + email/password |
| Database | Cloud Firestore (Spark plan) |
| File storage | Firebase Storage for resume bytes; Firestore holds metadata |
| LLM | Anthropic Claude (Haiku 4.5), called directly from Flutter |
| Job source | JSearch via RapidAPI, direct from Flutter |
| Email | Gmail API — user's own account; `gmail.compose` for drafts, `gmail.send` for confirmed sends; never read scope |
| Recipient lookup | Recipient Intelligence ranks confirmed cache, official-site discovery hooks, and low-confidence `careers@domain` guesses; Syncra never guarantees an inbox is valid |
| Job Trust Guard | Heuristic red-flag screen only; never certifies a job as legitimate |
| Secrets | `--dart-define=KEY=...` at build time; rotate after demo |
| Agent paradigm | Tool use — Claude picks tools, client executes, loop continues |
| Human-in-the-loop | Claude never sends external traffic directly; manual sends require a user tap, while Autopilot sends require the app safety gate |
| Resume canonical form | `ResumeJSON` in Firestore, lazy-populated on first parse |
| PDF template | One fixed single-column ATS-safe layout |
| Resume integrity | Pure Dart check after accepted edits render, with deterministic skill cleanup and one guarded repair pass; no extra PDF editor |
| State management | `flutter_riverpod` — every controller a `Notifier<T>` with immutable state |

**Decisions settled from earlier open questions:** PDF may overflow to page 2;
tailoring feeds Claude the full job description; malformed parse JSON retries
once then surfaces an error; deleting a manual resume cascade-deletes its
tailored children; Gmail scopes are compose/send only; email/password auth is
wired through Firebase instead of guest fallback.

## 1. The agent loop

There is **one** agent. "Passive" vs "active" is just two triggers for the same
`AnthropicChatService.runAgent` loop:

- **Chat trigger** — user types a prompt; chat shows tool calls live.
- **Brief trigger** — user taps "Run today's brief"; `PassiveAgentNotifier.runBrief()`
  fires a canned prompt (*"Find 5 fresh jobs matching my profile, score them,
  save each as a pipeline card"*). Same loop, same tools.

The brief is not a background daemon. Returning signed-in users may be routed to
`MorningBriefPage` once per app session when `PassiveAgentState.morningBriefShown`
is still false. The actual brief only runs after an explicit page/CTA action calls
`PassiveAgentNotifier.runBrief()`.

```ff
trigger: user prompt  OR  canned brief prompt
   → AnthropicChatService.runAgent(messages, tools[])
   → Claude responds with:
       tool_use  → execute tool, append result, loop
       text      → emit TextBlock, done
       ask_user  → emit InputRequestBlock, pause for input, then resume
   → events route to: chat UI (if open) + notifications inbox (always)
```

Approval continuation works the same way as `ask_user`, but the user action comes
from an approval UI instead of a typed answer:

- `ProposedEditsBlock` — PR-style resume edits from `tailor_resume`; supports per-edit Accept/Reject decisions, Apply N edits, preview rendering, Resume Integrity Check status, save-to-library, and saved-resume continuation.
- `ActionProposalBlock` — approval card for concrete next actions; may include a hidden `continuationPrompt` that resumes the threaded agent loop after user approval.
- `send_email` remains gated. The agent may draft outreach, but Claude cannot send directly; manual sends require the email review UI token, and Autopilot sends require the app's central safety gate plus the same token path.

**Extended thinking is enabled** (`budget_tokens: 2048`, `max_tokens: 4096`).
Thinking blocks render as a collapsed "Thought for a moment" step and must be
returned verbatim in the next assistant message — the loop records assistant
`content` as-is. `redacted_thinking` is kept in history, hidden from UI.

**Retry:** transient failures (429 / 5xx / 529) retry up to 4× with exponential
backoff honoring `Retry-After`. Auth / bad-request errors fail immediately.
The loop iteration cap is 8.

## 2. State management — Riverpod

Every controller is a `Notifier<T>` exposing an immutable state class. Files end
in `_notifier.dart`. Widgets use `ref.watch(xProvider)` for state and
`ref.read(xProvider.notifier).method()` for actions. Never call `state = ...`
outside a notifier; never expose mutable lists/maps in a state class.

| Provider | State (key fields) | Key notifier methods |
| --- | --- | --- |
| `authProvider` | `AuthState` — `appUser`, `isLoading`, `error` | `signInWithGoogle`, `signOut`, `continueAsGuest`, `deleteAccount` |
| `userProfileProvider` | `UserProfile?` — `role`, `autonomyLevel`, `morningBriefEnabled`, `gmailConnected` | `setAutonomyLevel`, `setMorningBriefEnabled`, `setRole`, `setAgentActive` |
| `resumeProvider` | `ResumeState` — `allResumes`, `resumes`, `tailoredResumes`, `uploadQueue`, `selectedResumeIds` | `pickAndUploadResumes`, `deleteResume`, `toggleSelectedResume` |
| `applicationsProvider` | `ApplicationsState` — `items`, `filtered`, `filter` | `setFilter`, `markSent`, `addNote`, `updateNote`, `deleteNote` |
| `jobsProvider` | `JobsState` — `cards`, `pendingCards`, `savedIds` | `toggleSaved`, `hide`, `dismiss`, `approveByJobId` |
| `passiveAgentProvider` | `PassiveAgentState` — `status`, `pipeline`, `lastBriefAt` | `runBrief` (user-tap only) |
| `notificationsProvider` | `NotificationsState` — `items`, `unreadCount` | `setFilter`, `markRead`, `onAgentEvent` |
| `agentChatProvider` | `AgentChatState` — `items`, `isStreaming` | `sendPrompt`, `submitInputAnswer` |
| `agentServiceProvider` | `AgentService` singleton | `AnthropicChatService` if `ANTHROPIC_API_KEY` set, else `MockAgentService` |
| `routerProvider` | `GoRouter` singleton | redirects on `authProvider` + `userProfileProvider` |

Auth-derived providers (`resumeProvider`, `jobsProvider`, etc.) `ref.watch(authProvider)`
in `build()` so their Firestore streams rebind on user change. Adding a provider
updates this table.

**Proposed-edits state.** The current tailor flow renders a read-only
`ProposedEditsBlock` change log. Edits are shown with original text, proposed
text, and reason; the app renders an unsaved tailored preview and lets the user
save or dismiss the result. Per-edit accept/reject state is retained in the data
shape for future review support, but v1 does not require the user to accept each
edit individually.

## 3. Tools

Each tool is declared in `tool_registry.dart` (`name`, `description`,
`inputSchema`, `handler`, `requiresConfirmation`) and registered in
`builtin_tools.dart`.

| Tool | Purpose | Gating |
| --- | --- | --- |
| `search_jobs` | Search live listings; returns ≤25 `Job`s | auto |
| `read_resume` | Load the user's `ResumeJSON`; lazy-parses the PDF on first call | auto |
| `match_jobs` | Score jobs vs resume → category, score, justification, missing skills | auto |
| `check_job_risk` | Run a quick Trust Guard red-flag screen for a job | auto; asks before continuing on medium/high risk |
| `tailor_resume` | **Propose** 3–8 targeted edits for a job. No PDF, no write. | auto, then pause |
| `apply_resume_edits` | Apply the accepted edit subset → render PDF → new resume doc | **user-gated** — fired by the diff viewer, never by Claude |
| `resolve_company_contact` | Resolve recipient metadata before outreach: email, domain, confidence, source, reason, auto-send eligibility | auto; must run before `draft_email` |
| `draft_email` | Draft a cold-outreach email for a job, using a tailored resume | auto; user reviews before send |
| `lookup_hiring_manager` | Legacy alias for recipient resolution; prefer `resolve_company_contact` | auto |
| `remember_fact` | Persist a reusable fact about the user → `learned_facts` | auto |
| `save_to_pipeline` | Write a scored match as a pipeline card, including Trust Guard result | auto |
| `save_to_tracker` | Persist an application record to the Applications page, including Trust Guard result | auto; external sends still require the `send_email` user gate |
| `send_email` | Send the drafted email via Gmail | **never callable by Claude directly**; manual sends require a user tap, Autopilot sends require the central safety gate |
| `ask_user` | Ask the user a question and pause; optional suggestion chips | pauses the loop |

### The resume diff flow — the core sequence

1. `tailor_resume` returns `{ proposed_edits: [{ target_path, original_text,
   proposed_text, reason }] }`. `target_path` is a JSON path into `ResumeJSON`
   (e.g. `experience[0].bullets[2]`); `original_text` must match the resume
   verbatim — mismatches are dropped. **3–8 edits, bullet-level, never invents
   experience, employers, dates, metrics, tools, skills, or duplicate skill-list
   artifacts.**
2. The loop **pauses** — Claude must not auto-call `apply_resume_edits` or
   `draft_email`.
3. The user reviews edits in the inline `ProposedEditsBlock` change log.
4. The UI applies the proposed edits into an unsaved tailored preview via
   `ResumeDiffService.apply`, runs `ResumeQualityService.cleanTailoredResume`
   to remove duplicate skills and
   repeated skill-list artifacts, renders an unsaved preview, then runs
   `ResumeIntegrityService.verify` against the original `ResumeJSON`, tailored
   `ResumeJSON`, accepted edits, and applied/skipped counts.
5. The integrity result is deterministic and pure Dart. It checks protected
   identity/contact facts, unsupported companies/roles/schools/dates/metrics,
   skipped edits, and obvious section loss. It does **not** call Claude and does
   **not** use an external PDF editor.
6. `verified` can save normally. `needsReview` or `blocked` automatically queues
   one threaded repair turn that must call `tailor_resume` again for the same
   source resume/job and then stop at a replacement diff. Save is disabled while
   that repair is running. If the replacement still returns `needsReview`, the
   user may manually review/save with warning copy; if it still returns
   `blocked`, saving remains disabled and the preview stays visible.
7. "Fix with Syncra" from the tailored preview uses the same continuation path:
   pop back to chat, ask for a replacement `tailor_resume` diff, and forbid
   `apply_resume_edits`, `draft_email`, or `send_email` during the repair turn.
8. Once the user taps Save, a new Firestore resume doc is created
   (`source: 'tailored'`, `parent_resume_id`, `tailored_for_job_id`) and the
   saved resume id feeds back into the loop; Claude proceeds (typically to
   `draft_email`).

### Trust Guard contract

`check_job_risk` is a lightweight red-flag screen, not a background check or
legitimacy certificate. It evaluates the saved job text for obvious signals such
as missing company identity, thin descriptions, generic/confidential employers,
money-transfer language, gift-card requests, crypto/payment wording, or moving
communication to Telegram/WhatsApp.

The result shape is reused by the agent tool, pipeline cards, job action sheet,
and application tracker:

```json
{
  "risk_level": "low | medium | high",
  "risk_label": "Looks normal | Needs verification | High risk",
  "signals": [
    { "severity": "medium | high", "label": "...", "detail": "..." }
  ],
  "safe_next_step": "..."
}
```

### Tool input notes

- **`resolve_company_contact`** — `{ job_id?, company?, website?, apply_link? }`.
  Uses the employer website for domain extraction when available, then checks
  `company_contacts`, then the safe discovery shell, then falls back to
  `careers@domain` as `confidence: low`, `source: guessedPattern`,
  `canAutoSend: false`. No LinkedIn, social-media, private-profile scraping, or
  browser automation is allowed.
- **`draft_email`** — `{ job_id, resume_id, recipient_email?, recipient_name?,
  tone? }`. Drafts against the tailored resume identified by `resume_id` and
  returns recipient metadata (`recipientConfidence`, `recipientSource`,
  `recipientSourceUrl`, `recipientReason`, `canAutoSend`). The agent must stop
  after drafting; the review UI is the send/draft gate.
- **`save_to_tracker`** — `{ job_id, resume_id?, mark_sent? }`. `mark_sent` is a
  bool, default `false` (there is no `status` enum). In v1 this records prepared
  or sent work in the Applications activity log; actual external sending still
  goes through the `send_email` confirmation-token gate or a manual "Mark as sent".
- **`send_email`** — `{ to, subject, body, attachments? }`. On success the
  handler calls `applicationsRepo.markSent(uid, appId, sentEmailId: messageId)`.

## 4. Firestore data model

**`users/{uid}` — profile**

| Field | Type | Notes |
| --- | --- | --- |
| `name`, `email`, `avatar_url`, `role` | string | `role` captured in onboarding; empty role is allowed after Skip |
| `is_agent_active` | bool | Settings toggle for active agent behavior |
| `gmail_connected` | bool | Records Gmail connection/intent state |
| `has_completed_onboarding` | bool | Router gate for first-run onboarding |
| `resume_fit` | map? | persisted onboarding fit chart snapshot |
| `autonomy_level` | string | Agent Autonomy control: `assist` / `auto_draft` / `autopilot`; default `auto_draft`. User-facing dial that drives hidden Autopilot safety policy. |
| `auto_apply` | map | Hidden Autopilot safety policy derived from Agent Autonomy; not edited directly; defaults to Auto-draft policy |
| `created_at` | Timestamp | |

`auto_apply` map:

| Field | Type | Notes |
| --- | --- | --- |
| `enabled` | bool | derived from autonomy; only Autopilot sets `true` |
| `min_quality_score` | int | fixed policy value; clamped 60–100 |
| `max_daily_applications` | int | fixed policy value; clamped 0–10 |
| `require_low_trust` | bool | fixed `true`; requires Trust Guard `low` before eligibility |
| `auto_send_outreach` | bool | derived from autonomy; only Autopilot sets `true` |

Agent Autonomy is the single user-facing control. `auto_apply` is hidden safety
state, not a separately edited UI. Fixed mappings are:
Assist = off / quality 100 / daily 0 / low-trust required; Auto-draft = off /
quality 85 / daily 0 / low-trust required; Autopilot = on / auto-send outreach
on / quality 85 / daily 3 / low-trust required. Autopilot can only send when
the central safety gate passes: Autopilot mode, hidden settings on, draft phase,
daily cap, low trust, 85%+ quality, no application-bundle blockers, and a
confirmed/high-confidence recipient with `canAutoSend: true`. Guessed, missing,
or confirmation-required recipients never auto-send.

**`users/{uid}/applications/{appId}` — activity log**

| Field | Type | Notes |
| --- | --- | --- |
| `job` | map | embedded Job snapshot |
| `resume_id` | string | tailored resume used |
| `drafted_at` | Timestamp | |
| `sent_at` | Timestamp? | null = still a draft |
| `got_reply` | bool | user-flipped (no inbox scope) |
| `follow_up_at` | Timestamp? | optional reminder |
| `notes` | array<{body, created_at}> | free-form |
| `sent_email_id` | string? | Gmail message id |
| `trust_risk_level` | `unchecked \| low \| medium \| high` | Trust Guard level captured when saved |
| `trust_risk_label` | string | UI label: `Not checked`, `Looks normal`, `Needs verification`, `High risk` |
| `trust_signals_count` | int | number of saved Trust Guard signals |
| `trust_signals` | array<{severity, label, detail}> | signal details shown in the detail sheet |
| `trust_safe_next_step` | string | recommended verification step |
| `trust_checked_at` | Timestamp? | null when unchecked |

Open draft writes are idempotent by exact `job.id`: when `sent_at == null`,
agent/manual/autopilot flows reuse the existing draft instead of creating a
second open application. Legacy duplicate open drafts are deduped for tracker
filters and counts by keeping the newest `drafted_at` record.

**`users/{uid}/resumes/{resumeId}` — resume metadata**

| Field | Type | Notes |
| --- | --- | --- |
| `name`, `mime_type` | string | |
| `size` | int | |
| `source` | `manual \| tailored` | |
| `storage_path` | string | Firebase Storage path to the blob |
| `resume_json` | map? | lazy — written on first parse |
| `parent_resume_id`, `tailored_for_job_id` | string? | tailored only |
| `uploaded_at` | Timestamp | |

**`users/{uid}/pipeline/{cardId}`** — agent-generated job cards: `job`,
`category` (`ready \| input_needed \| exploration`), `match_score`,
`agent_action`, `agent_justification`, `matched_skills`, `missing_skills`,
`stage` (`matched \| tailored \| drafted \| sent \| replied`), `status`
(`pending \| approved \| dismissed`), Trust Guard fields
(`trust_risk_level`, `trust_risk_label`, `trust_signals_count`,
`trust_signals`, `trust_safe_next_step`, `trust_checked_at`), `created_at`.

### Pipeline lifecycle invariant

The active Jobs pipeline must only show unfinished pending work.

Pipeline cards use two separate axes:

- `stage`: progress through `matched`, `tailored`, `drafted`, `sent`, `replied`
- `status`: active visibility through `pending`, `approved`, `dismissed`

Important invariant:

- `matched`, `tailored`, and `drafted` cards may remain active while `status == pending`.
- `sent` and `replied` cards are handled work and must not appear in the active pipeline.
- Advancing a card to `sent` or `replied` must also mark the card `status: approved`.
- Legacy cards with `status: pending` but terminal stage `sent` or `replied` must still be hidden from the active pipeline.
- Pipeline saves are idempotent by exact `job.id`: one unfinished pending card is reused and updated; legacy active duplicates are collapsed by keeping the highest-stage/newest card and marking the others approved.
- Auto-draft/Autopilot skips a job that already has an open draft, advances its pipeline card to `drafted`, and does not auto-send that pre-existing draft.

Do not remove or weaken this behavior without updating `test/pipeline_repository_test.dart`.

**`users/{uid}/learned_facts/{factId}`** — `topic`, `detail`, `source`, `created_at`.

**`jobs/{jobId}`** — global job cache, upserted by `search_jobs`: title,
company, location, salary, description, source, source_url.

**`company_contacts/{domain}`** — shared confirmed recipient cache. JSearch does
not provide recruiter/company emails, so this cache is the preferred source when
a user has already confirmed an address. Docs may contain `email`, `domain`,
`company`, `source`, `confidence`, `sourceUrl`, `reason`, `confirmedBy`,
`confirmedCount`, `rejectedCount`, `updatedAt`, and `lastVerifiedAt`. Legacy
docs with only `email` decode as confirmed cache hits.

**`users/{uid}/conversations/{conversationId}`** — versioned chat workspace
snapshot. Current writes use `schemaVersion: 2` and store `title`,
`renamedTitle`, `lastPreview`, `pinned`, `updatedAt`, optional `threadJob`, and
serialized `items`.

`items` are encoded through `ChatSnapshotCodec` and can recover user bubbles,
resume attachment chips, agent text, tool-call rows, job-card rails,
proposed-edits cards with integrity results and repair flags, built-resume draft
cards, input-request cards, action proposal cards, and email draft cards. The drawer supports grouped history
sections, title/preview search, rename, pin/unpin, delete confirmation, and
preview text under each row.

Legacy text-only history is still supported. Unknown or malformed items/blocks
must skip safely rather than crashing the drawer or reopen flow. Running
stream/tool states are restored as stopped/failed snapshots, not resumed live.
After restore, `AnthropicChatService.restoreConversationContext()` rebuilds a
compact model-readable context summary from visible transcript blocks so the
next user message can continue naturally without pretending the tools reran.

## 5. Firebase Storage

````markdown
```text
gs://{bucket}/users/{uid}/
  ├── resumes/
  │   ├── {manual-resumeId}.pdf|.docx|.doc   ← uploaded by the user
  │   └── {tailored-resumeId}.pdf            ← saved generated resume
  └── conversation_previews/
      └── {conversationId}/{blockId}.pdf     ← unsaved chat preview PDF
```

Firestore resume docs carry `storage_path`. Unsaved chat preview PDFs are stored
only as `previewStoragePath` on the recovered chat block; no resume-library
Firestore doc is created until the user taps Save. On **Flutter Web**, Firebase
Storage CORS must allow browser downloads from the app origin — without it,
parsing and preview fail with `ClientException: Failed to fetch`. iOS / Android
use native SDKs and need no CORS. All platforms need Storage security rules.
Legacy docs without `storage_path` resolve to `null` bytes — the UI offers
re-upload.

## 6. External APIs

**Anthropic** — `POST https://api.anthropic.com/v1/messages`, model
`claude-haiku-4-5-20251001`. Headers: `x-api-key`,
`anthropic-version: 2023-06-01`, `anthropic-dangerous-direct-browser-access: true`.
Key: `ANTHROPIC_API_KEY`.

**JSearch (RapidAPI)** — `GET https://jsearch.p.rapidapi.com/search`. Headers:
`x-rapidapi-key`, `x-rapidapi-host: jsearch.p.rapidapi.com`. Key: `RAPIDAPI_KEY`.
Free tier 200 req/month — cache results in `jobs/`. JSearch job payloads do not
include verified recruiter or company inboxes.

**Gmail** — creates drafts with
`https://www.googleapis.com/auth/gmail.compose` on web and mobile after user
authorization, and sends only through the explicit review/tap path with
`https://www.googleapis.com/auth/gmail.send`. Web draft authorization uses
Firebase Auth's Google popup/reauth popup to obtain the provider OAuth access
token; non-web uses `google_sign_in` v7's `authorizationClient`. Draft creation
POSTs a base64url-encoded MIME message to `users/me/drafts`; confirmed sends POST
the same MIME payload to `users.messages.send`. Attachments, including resume
PDFs, ride as MIME parts. Syncra never requests Gmail read scopes and adds no
backend for Gmail.

Run locally:

```bash
flutter run \
  --dart-define=ANTHROPIC_API_KEY=sk-ant-... \
  --dart-define=RAPIDAPI_KEY=...
```

## 7. PDF template

One fixed single-column ATS-safe layout (black on white, no graphics), built in
`lib/features/resumes/services/pdf_template.dart` via `pw.Document`. Sections:
header, summary, experience, education, skills. Overflow to page 2 is allowed.
Tailored resumes render into the same template — the agent only paraphrases
text, never touches layout. Don't change the template without a team vote.

## 8. Rate limits & cost guards

| Surface | Cap |
| --- | --- |
| `search_jobs` (JSearch) | cache `jobs/` for 1h — stay under 200/month |
| `match_jobs` | ≤25 jobs per call |
| `tailor_resume` | one in-flight per session |
| `send_email` | hard-blocked without a review token or Autopilot safety path |
| Autopilot safety / auto-send outreach | external send only when Autopilot mode and hidden policy are enabled, Trust Guard is low, recipient confidence is confirmed/high with `canAutoSend: true`, and quality/daily/draft/bundle gates pass |
| Anthropic | $5/month spend cap in the console |

## 9. Chat job-result persistence

`JobsBlock` snapshots preserve three per-chat result sets:

- `dismissedJobIds` — roles the user dismissed from that chat result.
- `hiddenJobIds` — roles hidden from the current visible rail.
- `handledJobIds` — roles already acted on, such as saved to pipeline or used
  for an outreach draft.

Restored conversations must not bring dismissed or already-handled roles back as
fresh actions. This keeps old job rails consistent after refresh/restart and
matches the handled-job lifecycle used by the chat action sheet.

## 10. Security

- `firestore.rules` (deployed): `jobs/{jobId}` — any signed-in user read/write;
  `users/{uid}/**` — owner-only.
- `storage.rules` (deployed): `users/{uid}/resumes/**` and
  `users/{uid}/conversation_previews/**` — owner-only; writes capped at 5 MB and
  restricted to `application/*` content types.
- API keys ship compiled into the client via `--dart-define` for the v1 demo.
  **Rotate every key after the demo** and set spend caps in every provider
  console. Server-grade key management is deferred to a future Firebase Cloud
  Functions layer, not a non-Firebase backend.
