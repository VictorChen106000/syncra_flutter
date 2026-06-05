# Syncra — Architecture

How Syncra is wired. This is the **target contract**: if code disagrees with
this file, fix the code (or change this file by PR). Product context is in
[README.md](./README.md); current build status and ownership in
[STATUS.md](./STATUS.md).

## 0. Locked decisions

| Area | Decision |
| --- | --- |
| Platform | Flutter — iOS / Android / Web |
| Server | None. No FastAPI, no Cloud Functions. |
| Auth | Firebase Auth — Google Sign-In + email/password |
| Database | Cloud Firestore (Spark plan) |
| File storage | Firebase Storage for resume bytes; Firestore holds metadata |
| LLM | Anthropic Claude (Haiku 4.5), called directly from Flutter |
| Job source | JSearch via RapidAPI, direct from Flutter |
| Email | Gmail API — user's own account, `gmail.send` scope only |
| Hiring-manager lookup | None — outreach uses the company's generic `careers@` address |
| Job Trust Guard | Heuristic red-flag screen only; never certifies a job as legitimate |
| Secrets | `--dart-define=KEY=...` at build time; rotate after demo |
| Agent paradigm | Tool use — Claude picks tools, client executes, loop continues |
| Human-in-the-loop | Agent never sends external traffic without an explicit user tap |
| Resume canonical form | `ResumeJSON` in Firestore, lazy-populated on first parse |
| PDF template | One fixed single-column ATS-safe layout |
| State management | `flutter_riverpod` — every controller a `Notifier<T>` with immutable state |

**Decisions settled from earlier open questions:** PDF may overflow to page 2;
tailoring feeds Claude the full job description; malformed parse JSON retries
once then surfaces an error; deleting a manual resume cascade-deletes its
tailored children; Gmail scope is `gmail.send` only; email/password auth is
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
is still false; devs can force-preview it with `DevFlags.showMorningBrief`.
The actual brief only runs after an explicit page/CTA action calls
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

- `ProposedEditsBlock` — PR-style resume edits from `tailor_resume`; supports per-edit Accept/Reject decisions, Apply N edits, preview rendering, save-to-library, and saved-resume continuation.
- `ActionProposalBlock` — approval card for concrete next actions; may include a hidden `continuationPrompt` that resumes the threaded agent loop after user approval.
- `send_email` remains gated. The agent may draft outreach, but sending requires the email review UI and an explicit user-confirmation token.

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
| `applicationsProvider` | `ApplicationsState` — `items`, `filtered`, `filter` | `setFilter`, `markSent`, `addNote` |
| `jobsProvider` | `JobsState` — `cards`, `pendingCards`, `savedIds` | `toggleSaved`, `hide`, `dismiss`, `approveByJobId` |
| `passiveAgentProvider` | `PassiveAgentState` — `status`, `pipeline`, `lastBriefAt` | `runBrief` (user-tap only) |
| `notificationsProvider` | `NotificationsState` — `items`, `unreadCount` | `setFilter`, `markRead`, `onAgentEvent` |
| `agentChatProvider` | `AgentChatState` — `items`, `isStreaming` | `sendPrompt`, `submitInputAnswer` |
| `agentServiceProvider` | `AgentService` singleton | `AnthropicChatService` if `ANTHROPIC_API_KEY` set, else `MockAgentService` |
| `routerProvider` | `GoRouter` singleton | redirects on `authProvider` + `userProfileProvider` |

Auth-derived providers (`resumeProvider`, `jobsProvider`, etc.) `ref.watch(authProvider)`
in `build()` so their Firestore streams rebind on user change. Adding a provider
updates this table.

**Diff-viewer state (to build).** `ResumeState` must additionally hold the diff
session: `original` (V1, never mutated), `proposed` (V2 = original + accepted
edits), `pendingEdits`, `acceptedPaths`. `acceptEdit` / `rejectEdit` recompute
`proposed` via `ResumeDiffService.applyEdits`. See STATUS.md → Resume Diff UI.

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
| `draft_email` | Draft a cold-outreach email for a job, using a tailored resume | auto; user reviews before send |
| `lookup_hiring_manager` | The company's generic `careers@` address (no named-contact lookup) | auto |
| `remember_fact` | Persist a reusable fact about the user → `learned_facts` | auto |
| `save_to_pipeline` | Write a scored match as a pipeline card, including Trust Guard result | auto |
| `save_to_tracker` | Persist an application record to the Applications page, including Trust Guard result | auto; external sends still require the `send_email` user gate |
| `send_email` | Send the drafted email via Gmail | **always requires a user tap** |
| `ask_user` | Ask the user a question and pause; optional suggestion chips | pauses the loop |

### The resume diff flow — the core sequence

1. `tailor_resume` returns `{ proposed_edits: [{ target_path, original_text,
   proposed_text, reason }] }`. `target_path` is a JSON path into `ResumeJSON`
   (e.g. `experience[0].bullets[2]`); `original_text` must match the resume
   verbatim — mismatches are dropped. **3–8 edits, bullet-level, never invents
   experience, employers, dates, or metrics.**
2. The loop **pauses** — Claude must not auto-call `apply_resume_edits` or
   `draft_email`.
3. The user reviews edits in the inline `ProposedEditsBlock` and taps
   "Apply N edits".
4. The UI calls `apply_resume_edits` with `{ resume_id, accepted_edits }` →
   `ResumeDiffService.applyEdits` builds the V2 `ResumeJSON` → `pdf_template`
   renders → a new Firestore resume doc is created (`source: 'tailored'`,
   `parent_resume_id`, `tailored_for_job_id`) → returns `{ tailored_resume_id }`.
5. That result feeds back into the loop; Claude proceeds (typically to
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

- **`draft_email`** — `{ job_id, resume_id, recipient_email?, recipient_name?,
  tone? }`. Drafts against the tailored resume identified by `resume_id`.
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
| `auto_apply` | map | bounded auto-apply guardrails; defaults disabled |
| `created_at` | Timestamp | |

`auto_apply` map:

| Field | Type | Notes |
| --- | --- | --- |
| `enabled` | bool | default `false`; does not send/apply by itself |
| `min_quality_score` | int | default `85`; clamped 60–100 |
| `max_daily_applications` | int | default `3`; clamped 1–10 |
| `require_low_trust` | bool | default `true`; requires Trust Guard `low` before eligibility |

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

**`users/{uid}/learned_facts/{factId}`** — `topic`, `detail`, `source`, `created_at`.

**`jobs/{jobId}`** — global job cache, upserted by `search_jobs`: title,
company, location, salary, description, source, source_url.

**`users/{uid}/conversations/{conversationId}`** — persisted chat history:
conversation title, updated timestamp, and serialized chat items for the history
drawer/reopen flow.

## 5. Firebase Storage

```text

gs://{bucket}/users/{uid}/resumes/
  ├── {manual-resumeId}.pdf|.docx|.doc   ← uploaded by the user
  └── {tailored-resumeId}.pdf            ← rendered by apply_resume_edits

```

Firestore resume docs carry `storage_path`. On **Flutter Web**, Firebase Storage
CORS must allow browser downloads from the app origin — without it, parsing and
preview fail with `ClientException: Failed to fetch`. iOS / Android use native
SDKs and need no CORS. All platforms need Storage security rules. Legacy docs
without `storage_path` resolve to `null` bytes — the UI offers re-upload.

## 6. External APIs

**Anthropic** — `POST https://api.anthropic.com/v1/messages`, model
`claude-haiku-4-5-20251001`. Headers: `x-api-key`,
`anthropic-version: 2023-06-01`, `anthropic-dangerous-direct-browser-access: true`.
Key: `ANTHROPIC_API_KEY`.

**JSearch (RapidAPI)** — `GET https://jsearch.p.rapidapi.com/search`. Headers:
`x-rapidapi-key`, `x-rapidapi-host: jsearch.p.rapidapi.com`. Key: `RAPIDAPI_KEY`.
Free tier 200 req/month — cache results in `jobs/`.

**Gmail** — the existing Google Sign-In credential plus scope
`https://www.googleapis.com/auth/gmail.send`, requested on demand through
`google_sign_in` v7's `authorizationClient`. Sends a raw POST to
`users.messages.send` with a base64url-encoded MIME message (no `googleapis`
package needed); the PDF resume rides as an `application/pdf` part.

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
| `send_email` | hard-blocked without a user tap |
| Bounded auto-apply | eligibility/settings only in v1; no autonomous external submit/send |
| Anthropic | $5/month spend cap in the console |

## 9. Security

- `firestore.rules` (deployed): `jobs/{jobId}` — any signed-in user read/write;
  `users/{uid}/**` — owner-only.
- `storage.rules` (deployed): `users/{uid}/resumes/**` — owner-only; writes
  capped at 5 MB and restricted to `application/*` content types.
- API keys ship compiled into the client via `--dart-define`. **Rotate every key
  after the demo** and set spend caps in every provider console. Server-grade
  key management is out of scope (it would need a server).
