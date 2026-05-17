# Role 2 — Backend: API Fetch (JSearch + Gmail)

**Estimated:** 14-18 hours of core work (the heaviest greenfield track)
**Branch suggestion:** `r2-api-fetch`

---

## The 30-second context

Syncra is a Flutter AI career copilot. Stack: **Flutter + Firebase + Anthropic
Claude + JSearch + Gmail API**. No backend server. Demo target: June 16, 2026.

The agent has 8 tools registered. **Two of them are stubs you need to make
real:** `search_jobs` (currently filters cached Firestore data — needs live
JSearch) and `send_email` (currently returns "not sent"). You also wire the
optional `lookup_hiring_manager` via Hunter.io if time allows.

This is the heaviest greenfield track — most of your work is creating files
that don't exist yet.

## What's already shipped in YOUR area

- **Tool stubs registered** in
  [lib/features/agent_chat/tools/builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart):
  - `search_jobs` handler (~lines 60-105) — reads `jobs/` collection, filters
    client-side. Needs to be rewritten to call live JSearch.
  - `send_email` handler (~lines 515-549) — returns "not sent (Gmail wiring
    pending)". Needs Gmail API.
  - `lookup_hiring_manager` handler (~lines 413-446) — returns
    `careers@{domain}.com` guess. Optional Hunter.io upgrade.
- **`AnthropicParaphraseService.draftColdEmail()`** in
  [lib/features/agent_chat/tools/anthropic_tool_calls.dart](../../lib/features/agent_chat/tools/anthropic_tool_calls.dart) —
  drafts the email body. You don't touch this. You just send the result.
- **Google Sign-In** in
  [lib/features/auth/services/google_auth_service.dart](../../lib/features/auth/services/google_auth_service.dart) —
  works but currently only requests basic scopes. You'll need to add
  `gmail.send` (coordinate with Role 4).

## What you need to build

In priority order.

### 1. JSearch service (~5h)

**Create `lib/data/services/jsearch_service.dart`** — direct HTTP client for
JSearch via RapidAPI.

The old Python backend at `backend/app/jobs/sources.py` had a working
implementation — port it from Python to Dart. (The Python file was deleted
during migration; check git history with `git log --diff-filter=D --name-only`
if you need to reference it.)

Behavior:
- Endpoint: `https://jsearch.p.rapidapi.com/search`
- Params: `query`, `page=1`, `num_pages=1`, `country=us`, `date_posted=week`
- Headers: `x-rapidapi-key` (from `--dart-define=RAPIDAPI_KEY=...`),
  `x-rapidapi-host: jsearch.p.rapidapi.com`
- Map JSearch response → our `Job` model in
  [lib/data/models/job.dart](../../lib/data/models/job.dart)
- **Deterministic IDs** — `_jobIdFor(title, company, source_url)` using
  SHA256. Same job from JSearch on different days should produce the same id
  so Firestore upserts coalesce.
- **Trim long descriptions** to ~500 chars before storing — JSearch returns
  10 KB descriptions; we don't need that.

### 2. In-memory cache for JSearch (~1-2h)

JSearch's free tier is 200 req/month. You'll burn through it fast in dev.

In your `JsearchService`:
- Map keyed on `(query, location)` → `(timestamp, results)`.
- TTL: 1 hour.
- Cache hit → return without HTTP.
- Cache miss → fetch, store, return.

### 3. Replace the `search_jobs` tool handler (~2h)

In [builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart),
function `_registerSearchJobs`:
- Replace the current `repo.fetchAll(40)` + client-side filter logic.
- Instead: call `jsearchService.search(query, location, limit)`.
- After fetching, upsert each result into `jobs/` via `JobsRepository`
  (you may need to add an `upsert` method — coordinate with Role 1 if it
  touches the resume repo, but jobs repo should be safe).
- Keep the tool's response shape **identical** so Claude's downstream tool
  calls (`match_jobs`, `tailor_resume`) don't change.

### 4. Gmail service (~6-8h, the trickiest piece)

**Create `lib/features/email/services/gmail_service.dart`.**

Add to pubspec:
```yaml
googleapis: ^13.0.0
googleapis_auth: ^1.6.0
```

Behavior:
- Use the existing `GoogleSignIn` instance from
  [lib/features/auth/services/google_auth_service.dart](../../lib/features/auth/services/google_auth_service.dart).
- **Add the `gmail.send` scope** to the Google Sign-In config — coordinate
  with Role 4 (they own [google_auth_service.dart](../../lib/features/auth/services/google_auth_service.dart)
  config). On iOS this may trigger a re-consent screen for users who already
  signed in.
- Build a MIME message:
  - Headers: `From`, `To`, `Subject`, `Content-Type: multipart/mixed`
  - Body part: `text/plain` with the drafted body
  - Attachment part: `application/pdf` with the tailored resume bytes, named
    e.g. `Resume.pdf`
- Base64url-encode the whole MIME message
- POST to `users.messages.send` via `googleapis`:
  ```dart
  await gmailApi.users.messages.send(Message(raw: base64UrlMessage), 'me');
  ```
- Return the Gmail `messageId`.

### 5. Wire the `send_email` tool — but gate it behind a confirmation token (~1-2h)

**Critical: never auto-send.** The agent must NOT be able to fire `send_email`
without explicit user tap on the review modal (built by Role 5).

In `_registerSendEmail` in [builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart):
- Add a `confirmation_token: string?` to the tool's input schema.
- Handler refuses to send unless the token matches a one-shot UUID that Role
  5's modal generated.
- Token validation: an in-memory map keyed by token, set by Role 5 when user
  taps Send, popped + validated here, single-use.

**Coordinate with Role 5 on token shape in week 1.** Suggested:
- Role 5's modal generates a UUID, stores it in `EmailGateService.armToken(token)`.
- Role 5's modal passes the token to the agent's resumePrompt or directly invokes
  the tool with the token.
- Your handler calls `EmailGateService.consumeToken(token)` — returns `true` only once.

### 6. (Optional stretch) Hunter.io for hiring-manager lookup (~3h)

**Create `lib/data/services/hunter_service.dart`.**
- Endpoint: `https://api.hunter.io/v2/domain-search`
- Params: `domain={inferred from company}`, `api_key={from --dart-define=HUNTER_API_KEY}`
- Free tier: 25 searches/month — cache aggressively (by company, 24h TTL).
- Replace `_registerLookupHiringManager` handler to call Hunter, fall back to
  `careers@{domain}.com` if Hunter has no results.

Only do this if you have a couple of hours left after the must-haves. Demo
works without it.

## Files you own

```
lib/data/services/                           ← CREATE this folder
├── jsearch_service.dart                     ← create
└── hunter_service.dart                      ← create (stretch)

lib/features/email/                          ← CREATE this folder
└── services/
    └── gmail_service.dart                   ← create

lib/features/agent_chat/tools/builtin_tools.dart  ← edit 3 handlers:
                                                  ← _registerSearchJobs
                                                  ← _registerSendEmail
                                                  ← _registerLookupHiringManager (stretch)
```

## You're done when

- Type *"find UX designer jobs in Singapore"* in chat → real, current Singapore
  listings come back (not the seeded data).
- Type *"send the application"* in chat → email actually arrives in the
  recipient's inbox, from the user's Gmail, with the tailored PDF attached.
- (Stretch) Mentioning a specific company in `draft_email` produces a real
  hiring-manager email when Hunter has data.

## Coordination handshakes — week 1

| Handshake | With | Lock in week 1 |
|---|---|---|
| Add `gmail.send` OAuth scope | Role 4 (Shell) | They update the GoogleSignIn config + you test it boots |
| Confirmation token shape for `send_email` | Role 5 (Surfaces) | Agree on token type + how the modal arms it |

## Common pitfalls

- **JSearch returns A LOT of data.** Trim before storing.
- **Don't cache by raw URL** — JSearch returns the same job with different
  `job_apply_link` values. Use the `_jobIdFor(title, company, source_url)`
  deterministic hash.
- **Gmail OAuth needs Google Cloud Console setup.** The Firebase project
  (`syncra-signlogin`) already has OAuth client IDs for Google Sign-In — you
  enable the Gmail API for the same project at
  https://console.cloud.google.com/apis/library/gmail.googleapis.com.
- **iOS may need `Info.plist` update** for new OAuth scopes — test on a real
  iPhone, not just simulator.
- **Never log API keys.** `debugPrint` your way around them.
- **Set a monthly Anthropic spend cap of $5** in the console. If prompts loop
  badly, costs can spike.

## Relevant contract sections

- [api-contract.md §2.1 search_jobs](../api-contract.md) — tool spec
- [api-contract.md §2.5 draft_email](../api-contract.md) — already exists,
  you just need the send side
- [api-contract.md §2.6 lookup_hiring_manager](../api-contract.md) — stretch
- [api-contract.md §2.8 send_email](../api-contract.md) — your main spec
- [api-contract.md §5 External APIs](../api-contract.md) — endpoints,
  headers, keys
- [api-contract.md §6 Security & rules](../api-contract.md) — key delivery
  via `--dart-define`

## How to use this brief with your AI

Paste this entire file as your first message to Claude / ChatGPT / Copilot.
Then ask:

> *"Read this brief. I'm starting Role 2. Walk me through how to scaffold
> `jsearch_service.dart` first, then explain the Gmail OAuth dance."*

When you hit OAuth issues on a specific platform, paste the error + your
platform (iOS/Android) into the chat — those are the most-debugged class of
issue for Gmail integration.
