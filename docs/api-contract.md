# Syncra Architecture Contract

**Status:** Draft v1.3 — adds PR-diff resume tailoring + opt-in morning brief, replaces v1.1
**Demo target:** June 16, 2026
**Last updated:** 2026-05-20

Single source of truth for how Syncra is wired. If code disagrees with this
file, this file wins. Product context lives in [product-brief.md](./product-brief.md);
team ownership in [team-handoff.md](./team-handoff.md) (per-track work) and
[roles/](./roles/) (per-person briefs).

---

## 0. Locked decisions (don't re-litigate)

| Decision | Choice |
|---|---|
| App platform | Flutter (iOS / Android / Web) |
| Server | **None.** No FastAPI, no Cloud Functions. |
| Auth | Firebase Auth — Google Sign-In only |
| Database | Cloud Firestore (Spark plan) |
| File storage | **Local device/session storage**. Mobile/desktop use `path_provider`; web uses browser `sessionStorage` as a temporary PDF-byte cache. No Firebase Cloud Storage. |
| LLM | Anthropic Claude (Haiku 4.5) — direct from Flutter |
| Job source | JSearch via RapidAPI — direct from Flutter |
| Email send | Gmail API (user's own account, OAuth) |
| Hiring-manager lookup | Hunter.io — optional stretch goal |
| API key delivery | `--dart-define=KEY_NAME=...` at build time |
| Agent paradigm | **Tool use** — Claude picks tools, client executes them, loop continues |
| Human-in-the-loop | Agent never sends external traffic without explicit user tap in v1 |
| Resume canonical form | `ResumeJSON` in Firestore (lazy-populated on first tailor) |
| Resume PDF | Local file at `${appDocs}/resumes/{resumeId}.pdf` |
| PDF template | One fixed single-column ATS-safe layout |
| Authorization | Owner-only Firestore rules on `users/{uid}/**` |

---

### Web preview cache

On Flutter Web, `path_provider` is not used because browser apps do not have a normal app documents directory. The app stores uploaded PDF bytes in browser `sessionStorage` so PDF preview survives hot reload, hot restart, and page reload in the same tab/session.

Behavior:
- Same browser tab/session: PDF preview can survive reload.
- Closed tab/window: browser `sessionStorage` is cleared, so preview requires re-upload.
- Different device/browser: Firestore metadata still appears, but the actual PDF bytes are missing.
- No Firebase Storage is used, keeping the project on the Spark/free-plan-safe architecture.

## 1. Agent loop — the primary UX

There is **one** agent. What looks like "passive" vs "active" agent in the UI
is just two **triggers** for the same `AnthropicChatService.runAgent` loop —
both now explicit user taps:

- **Chat trigger** — user types a prompt in the chat; chat shows the tool calls live.
- **Brief trigger** — user taps "Run today's brief" on the dashboard.
  [PassiveAgentNotifier.runBrief()](../lib/features/agent/state/passive_agent_notifier.dart)
  fires a canned prompt (*"Find 5 fresh jobs matching my profile, score them
  via match_jobs, and save each as a pipeline card via save_to_pipeline"*).
  Same code path, same tools. Tool-call progress lands in the notifications
  inbox; cards land on the pipeline page. `users/{uid}.last_brief_at` is
  written for the "Last brief: 2h ago" label, **but is never read to decide
  auto-firing**. There is no auto-fire on app open in v1.3 (this was a token-cost
  regression in v1.2). The dashboard CTA is hidden behind
  `morning_brief_enabled` in the user profile, off by default.

### The shape

```
┌──────────────────────────────────────────────────────────┐
│  trigger: user prompt  OR  system canned prompt          │
│         │                                                │
│         ▼                                                │
│  AnthropicChatService.runAgent(messages, tools[])        │
│         │                                                │
│         ▼                                                │
│  Claude responds with one of:                            │
│    (a) tool_use     → execute, append result, loop       │
│    (b) text         → emit TextBlock, done               │
│    (c) ask_user     → emit InputRequestBlock, pause      │
│         │                                                │
│         ▼                                                │
│  if (c), wait for user input → resume loop               │
│                                                          │
│  Events route to: chat UI (if user is there)             │
│                 + notifications inbox (always)           │
└──────────────────────────────────────────────────────────┘
```

### The pieces

| Piece | Where |
|---|---|
| Tool registry | `lib/features/agent_chat/tools/tool_registry.dart` (new) |
| Tool executor | `lib/features/agent_chat/tools/tool_executor.dart` (new) |
| Agent loop | `lib/features/agent_chat/services/anthropic_chat_service.dart` (extend existing) |
| New block: `InputRequestBlock` | `lib/features/agent_chat/models/agent_block.dart` (extend) |
| Decision-point cards | `agent_block_views.dart` (extend) |

### Human-in-the-loop rules

| Tool | Auto-runs? | Requires confirmation? |
|---|---|---|
| `search_jobs` | ✅ | No |
| `read_resume` | ✅ | No |
| `match_jobs` | ✅ | No |
| `tailor_resume` | ✅ | Returns proposed edits only — no PDF, no write |
| `apply_resume_edits` | ❌ | **User-gated.** Fired by the diff viewer's "Apply N edits" CTA, never by Claude |
| `draft_email` | ✅ | User reviews before send |
| `lookup_hiring_manager` | ✅ | No |
| `save_to_tracker` | Depends on `autonomy_level` | Writes to the Applications page. `suggest` → ask; `auto_apply` → just do it |
| `send_email` | ❌ | **Always requires user tap.** No exceptions in v1. |
| `ask_user` | n/a | Paused, awaits user typing |

---

## 1.5 State management — Riverpod providers

> **Migrated 2026-05-18 from `provider` → `flutter_riverpod` ^2.6.1.** Every
> controller is now a `Notifier<T>` exposing an **immutable** state class.
> Old `*_controller.dart` files were deleted; the new files end in `_notifier.dart`.
> Widget call sites use `ref.watch(xProvider)` for state, `ref.read(xProvider.notifier).method()` for actions.

This section is the reference for all tracks (backend included) on what state
each notifier exposes and what methods are callable. If you need to read or
write app state from inside a tool implementation, fetch the notifier off the
`Ref` you receive — never re-implement state ownership.

### How to access state from a tool handler

Tool implementations registered in [builtin_tools.dart](../lib/features/agent_chat/tools/builtin_tools.dart)
receive a `Ref` so they can reach into Riverpod. Examples:

```dart
// Read current user (e.g. for uid)
final uid = ref.read(authProvider).appUser?.uid;

// Persist a pipeline card via the notifier (preferred over hitting the repo directly)
await ref.read(jobsProvider.notifier).approveByJobId(jobId);

// Fire a chat block manually after a backend event resolves
ref.read(agentChatProvider.notifier).sendPrompt(prompt: ...);
```

Never call `state = ...` from outside the notifier. Always go through a method
on the notifier — that's the only place mutations are allowed.

### Provider reference table

| Provider | State class | Key fields | Notifier methods |
|---|---|---|---|
| `authProvider` | `AuthState` | `appUser`, `isLoading`, `error`, `isSignedIn` | `signInWithGoogle()`, `signOut()`, `continueAsGuest()`, `deleteAccount()` |
| `userProfileProvider` | `UserProfile?` (null for guests / unloaded) | `name`, `email`, `avatarUrl`, `role`, `isAgentActive`, `autonomyLevel` (`suggest`/`askFirst`/`autoApply`), `morningBriefEnabled`, `gmailConnected` | `setAutonomyLevel(level)`, `setMorningBriefEnabled(bool)`, `setRole(string)`, `setAgentActive(bool)` — all write through `UserRepository.update()` |
| `resumeProvider` | `ResumeState` | `allResumes`, `resumes` (manual), `tailoredResumes`, `uploadQueue`, `selectedResumeIds`, `selectedResumes`, `lastAction` | `pickAndUploadResumes()`, `deleteResume(id)`, `toggleSelectedResume(id)`, `removeSelectedResume(id)`, `consumeLastAction()` |
| `applicationsProvider` | `ApplicationsState` | `items`, `filtered`, `filter`, `lastMessage` | `setFilter(f)`, `updateStatus(appId, status)`, `addNote(appId, body)`, `consumeMessage()` |
| `jobsProvider` | `JobsState` | `cards`, `pendingCards`, `pendingJobs`, `savedIds`, `hiddenIds`, `dismissedIds`, `lastMessage`, `isSaved/isHidden/isDismissed(id)` | `toggleSaved(id)`, `hide(id)`, `unhide(id)`, `dismiss(id)`, `undismiss(id)`, `approveByJobId(jobId)`, `consumeMessage()` |
| `passiveAgentProvider` | `PassiveAgentState` | `status`, `pipeline`, `activity`, `lastBriefAt`, `lastError`, `morningBriefShown`, `isLiveModeEnabled`, `hasPipeline`, `isRunning`, `readyCount`, `inputNeededCount`, `explorationCount`, `topMatch` | `runBrief()` *(user-tap only — never auto-fire)*, `markMorningBriefShown()`, `consumeMessage()` |
| `notificationsProvider` | `NotificationsState` | `items`, `filtered`, `filter`, `unreadCount`, `lastMessage` | `setFilter(f)`, `markRead(id)`, `markAllRead()`, `consumeMessage()` |
| `agentChatProvider` | `AgentChatState` | `items` (`List<ChatItem>`), `isStreaming` | `sendPrompt({prompt, attachments})`, `acceptProposal(blockId)`, `dismissProposal(blockId)`, `submitInputAnswer(blockId, answer)` |
| `agentServiceProvider` | `AgentService` | n/a (singleton) | — chooses `AnthropicChatService` if `ANTHROPIC_API_KEY` set, else `MockAgentService` |
| `routerProvider` | `GoRouter` | n/a (singleton) | listens to `authProvider` for redirect refresh |

### Side-effect handshakes (one-time message channels)

Several states expose a `lastMessage` / `lastAction` field used as a one-shot
SnackBar channel. Pattern:

```dart
ref.listen<XState>(xProvider, (prev, next) {
  if (next.lastMessage == null || next.lastMessage == prev?.lastMessage) return;
  ref.read(xProvider.notifier).consumeMessage();   // clears it
  ScaffoldMessenger.of(context).showSnackBar(...);
});
```

If you write a `lastMessage` from a notifier method, the active page will
SnackBar it once. Don't poll this field — read it via `ref.listen`.

### Auth-derived providers — dependency direction

`userProfileProvider`, `resumeProvider`, `applicationsProvider`, `jobsProvider`,
`passiveAgentProvider` all `ref.watch(authProvider)` inside their `build()` so
their Firestore stream subscription rebinds whenever the signed-in user
changes. **Do not** add an `addListener(auth)` pattern anywhere — Riverpod
handles this automatically.

### Settings-gated UI

The dashboard `_RunBriefCta` only renders when
`userProfileProvider.morningBriefEnabled == true`. A brand-new account sees
no CTA until the user toggles it on in Settings (default `false` per §3).
The agent **never** auto-fires regardless of this flag — the toggle only
controls whether the manual trigger is visible.

### Router-gated UI

`routerProvider`'s redirect uses both `authProvider` and `userProfileProvider`:

- **Signed-out** + protected route → `/login`
- **Signed-in + non-guest + profile loaded + `role` empty** → `/onboarding`
  (one-shot; once the user submits a role, the redirect releases them to
  `/dashboard` or `/morningBrief`)
- **Signed-in + has role** sitting on `/onboarding` → `/dashboard`
- **Signed-in on `/login` or `/signup`** → `/morningBrief` (first sign-in of
  the session) or `/dashboard`

`profile == null` (stream still loading) is treated as "don't redirect to
onboarding yet" — the refresh listener will re-evaluate when the first
snapshot arrives.

### Hard rules (carry-over from migration)

- Never expose mutable lists/maps in state classes — copy on every mutation.
- Never call `state = ...` outside the notifier.
- Never re-add `provider` (the package) to `pubspec.yaml`.
- Adding a new provider requires updating this table.

---

## 2. Tools registry

### Schema

Every tool is declared once in `tool_registry.dart` with:
- `name`: snake_case identifier sent to Claude
- `description`: what it does — Claude reads this to pick
- `input_schema`: JSON Schema for the arguments
- `executor`: a Dart function `Future<ToolResult> Function(Map<String, dynamic> args, ToolContext ctx)`
- `requires_confirmation`: bool

### Tools for v1

#### 2.1 `search_jobs`
```yaml
name: search_jobs
description: Search live job listings. Returns up to 25 normalized Job records.
input_schema:
  query: string       # e.g. "senior UX designer"
  location: string?   # e.g. "Remote", "San Francisco"
  limit: int?         # default 10, max 25
backed_by: JSearch (RapidAPI) + Firestore jobs/ upsert
returns: list<Job>
```

#### 2.2 `read_resume`
```yaml
name: read_resume
description: Load the user's parsed resume as structured data. Parses lazily on first call.
input_schema:
  resume_id: string?    # defaults to most recent manual resume
backed_by: Firestore users/{uid}/resumes/{id} + lazy parse (syncfusion_flutter_pdf + Anthropic)
returns: ResumeJSON
side_effect: writes resume_json back to the doc the first time it parses
```

#### 2.3 `match_jobs`
```yaml
name: match_jobs
description: Score each job against the user's resume. Returns rank-ordered list with reasoning.
input_schema:
  job_ids: list<string>
  resume_id: string?
backed_by: Anthropic (existing AnthropicService.scoreJobs)
returns: list<MatchResult>  # category, match_score, justification, missing_skills
```

#### 2.4 `tailor_resume`
```yaml
name: tailor_resume
description: Propose targeted edits to the user's resume for a specific job.
  Returns a list of proposed edits — does NOT modify the resume and does NOT
  render any PDF. The user reviews each edit in the diff viewer before
  applying.
input_schema:
  resume_id: string
  job_id: string
backed_by: Anthropic (paraphrase only — never invents experience, employers, dates, or metrics)
returns:
  proposed_edits: list<ProposedEdit>
    # ProposedEdit = {
    #   target_path: string,    # JSON path into ResumeJSON, e.g. "experience[0].bullets[2]"
    #   original_text: string,  # verbatim current text at that path (validated by string match)
    #   proposed_text: string,  # rewritten version
    #   reason: string,         # one-sentence why this helps for THIS job
    # }
side_effect: none — the resume is not changed until the user accepts edits
  and FE2 calls apply_resume_edits
constraints:
  - 3-8 edits per call
  - every original_text must match the current resume verbatim; mismatched edits are dropped
  - prefer rewriting individual bullets over full-section rewrites
loop_behavior: after this tool returns, Claude must stop and wait. The user
  reviews edits in the diff viewer; FE2 fires apply_resume_edits with the
  accepted subset; the resulting tool_result feeds back into the loop and
  Claude then proceeds (typically to draft_email).
```

#### 2.4b `apply_resume_edits` *(new — user-triggered render step)*
```yaml
name: apply_resume_edits
description: Apply the subset of proposed edits the user accepted in the diff
  viewer, render the tailored PDF, and create a new resume document. Call only
  after the user has reviewed proposed_edits and tapped "Apply N edits" in the
  inline `ProposedEditsBlock` in the chat.
input_schema:
  resume_id: string             # the original resume
  accepted_edits: list<ProposedEdit>
returns: { tailored_resume_id }
backed_by: resume_diff_service.applyEdits (pure, deterministic) → pdf_template render → resumes_repository
side_effect: renders to PDF, saves to local disk, creates new Firestore resume
  doc with source='tailored', parent_resume_id=<original>, tailored_for_job_id=<job>
caller: FE2's diff viewer dispatches this via the chat controller. Claude must
  not call this tool directly — it is user-gated.
```

#### 2.5 `draft_email`
```yaml
name: draft_email
description: Draft a cold-outreach email for a job, using a tailored resume.
input_schema:
  job_id: string
  resume_id: string
  recipient_email: string?
  recipient_name: string?
  tone: 'warm' | 'direct' | 'curious'   # default 'warm'
backed_by: Anthropic
returns: { subject, body, recipient }
```

#### 2.6 `lookup_hiring_manager` (stretch)
```yaml
name: lookup_hiring_manager
description: Find a likely hiring manager + email at a target company.
input_schema:
  company: string
  role_filter: string?   # e.g. "design", "engineering"
backed_by: Hunter.io domain search
returns: { name?, email?, confidence_score }
```

#### 2.6a `remember_fact` *(new — learning across sessions)*
```yaml
name: remember_fact
description: Persist a fact about the user that came up during conversation
  (skills, preferences, missing experience the user disclosed). Future agent
  turns read these via read_resume so the user doesn't get asked the same
  question twice. Call this whenever the user answers an ask_user with
  information that would apply beyond the current task.
input_schema:
  topic: string         # short slug, e.g. "ab_testing", "remote_preference"
  detail: string        # one or two sentences with the actual fact
returns: { fact_id }
backed_by: Firestore users/{uid}/learned_facts/{factId}
```

#### 2.6b `save_to_pipeline`
```yaml
name: save_to_pipeline
description: Write a scored job match to the user's pipeline as an approval card.
  Used by the morning-brief flow to persist agent-prepared recommendations.
input_schema:
  job_id: string
  category: 'ready' | 'input_needed' | 'exploration'
  match_score: int           # 0-100, sort-only
  agent_action: string       # short verb phrase, e.g. "Ready to send"
  agent_justification: string # one-sentence reasoning
  matched_skills: list<string>
  missing_skills: list<string>
backed_by: PipelineRepository.createCard
returns: { card_id }
```

#### 2.7 `save_to_tracker`
```yaml
name: save_to_tracker
description: Persist an application record to the user's tracker.
input_schema:
  job_id: string
  resume_id: string
  status: 'submitted' | 'drafting'
  next_step: string?
backed_by: Firestore users/{uid}/applications
returns: { application_id }
```

#### 2.8 `send_email`
```yaml
name: send_email
description: Send the drafted email from the user's Gmail account. ALWAYS asks for explicit user confirmation.
input_schema:
  to: string
  subject: string
  body: string
  attachments: list<{ resume_id }>?
backed_by: Gmail API (OAuth, send scope)
returns: { message_id, sent_at }
requires_confirmation: true (modal "Send to X?" — user must tap)
```

#### 2.9 `ask_user`
```yaml
name: ask_user
description: When the agent needs information only the user can provide, ask them and pause.
input_schema:
  question: string
  suggestions: list<string>?   # quick-reply chips
  input_type: 'short_text' | 'long_text' | 'choice'
returns: { answer: string }   # filled in after user types
ui: emits InputRequestBlock — chat shows a text field + optional suggestion chips
```

---

## 3. Firestore data model

### `users/{uid}` — profile
| Field | Type | Notes |
|---|---|---|
| `name`, `email`, `avatar_url`, `role` | string(?) | `role` is captured in onboarding |
| `is_agent_active` | bool | |
| `autonomy_level` | `'suggest' \| 'ask_first' \| 'auto_apply'` | default `'ask_first'`. Set in Settings, **not** onboarding |
| `morning_brief_enabled` | bool | default `false`. When false, the dashboard "Run today's brief" CTA is hidden. **Never** triggers an auto-fire — even when true, the brief requires a tap |
| `gmail_connected` | bool | |
| `gmail_refresh_token` | string? | encrypted; v2 |
| `created_at` | Timestamp | |
| `last_brief_at` | Timestamp? | Written by `runBrief()` for the "Last brief: 2h ago" label. **Display-only** — never read to decide whether to auto-fire |

### `users/{uid}/applications/{appId}` — Activity log (was tracker)
**Schema simplified in v1.2 to match what the system can actually observe.**
The old multi-stage `status` enum (viewed/replied/interview/offer/rejected) was
removed — we don't read the user's inbox, so those statuses would have stayed
stuck at `submitted` forever, looking broken in the demo. Now: drafted, sent,
and user-flipped flags only.

| Field | Type | Notes |
|---|---|---|
| `job` | map | Embedded Job snapshot |
| `resume_id` | string | Tailored resume used for this application |
| `drafted_at` | Timestamp | When the agent prepared the draft |
| `sent_at` | Timestamp? | When the user tapped Send (null = still drafting) |
| `got_reply` | bool | User-flippable toggle — manual since no inbox scope |
| `follow_up_at` | Timestamp? | Optional reminder set by the user |
| `notes` | array<{body, created_at}> | Free-form user notes |
| `sent_email_id` | string? | Gmail message id, set when send_email succeeds |

### `users/{uid}/learned_facts/{factId}` *(new collection)*
Persistent facts the agent learned from `ask_user` answers. Read by future
agent turns so the same question isn't asked twice.

| Field | Type |
|---|---|
| `topic` | string |
| `detail` | string |
| `source` | `'user' \| 'resume'` |
| `learned_at` | Timestamp |

### `users/{uid}/pipeline/{cardId}` — agent-generated job cards
| Field | Type |
|---|---|
| `job` | map |
| `category` | `'ready' \| 'input_needed' \| 'exploration'` |
| `match_score` | int |
| `agent_action`, `agent_justification`, `why` | string |
| `matched_skills`, `missing_skills` | array<string> |
| `status` | `'pending' \| 'approved' \| 'dismissed'` |
| `tailored_resume_id` | string? |
| `created_at` | Timestamp |

### `users/{uid}/resumes/{resumeId}` — resume metadata
| Field | Type |
|---|---|
| `name`, `mime_type` | string |
| `size` | int |
| `source` | `'manual' \| 'tailored'` |
| `local_path` | string |
| `uploaded_at` | Timestamp |
| `resume_json` | map? (lazy) |
| `parent_resume_id`, `tailored_for_job_id` | string? (tailored only) |

### `users/{uid}/conversations/{convId}/messages/{msgId}` — chat history (v2)
v1 keeps chat in-memory. Schema is here so adding persistence later is a one-day job.

### `jobs/{jobId}` — global cache
Title, company, location, salary, description, source, source_url, discovered_at.
Filled by `search_jobs` upserts. Pre-seeded by legacy backend's JSearch sync.

---

## 4. Local device storage

```
${appDocumentsDirectory}/
└── resumes/
    ├── {manual-resumeId}.pdf       ← user-uploaded
    └── {tailored-resumeId}.pdf     ← generated by tailor_resume
```

Same device = both work. New device = Firestore doc exists, file missing, UI offers re-upload.

---

## 5. External APIs

### 5.1 Anthropic
- Endpoint: `https://api.anthropic.com/v1/messages`
- Model: `claude-haiku-4-5-20251001`
- Tool use: pass tool definitions in the request; loop on `tool_use` responses
- Header: `x-api-key`, `anthropic-version: 2023-06-01`, `anthropic-dangerous-direct-browser-access: true`
- Key: `--dart-define=ANTHROPIC_API_KEY=sk-ant-...`
- `max_tokens: 4096` — must stay above the thinking budget below.
- **Extended thinking: enabled.** Request carries `thinking: { type: "enabled", budget_tokens: 2048 }`. The response `content` array gains `thinking` blocks (and occasionally `redacted_thinking`); the loop emits each `thinking` block as a `ThinkingBlock` and renders it as the collapsed "Thought for a moment" timeline step. `redacted_thinking` blocks are skipped from the UI but kept in history.
  - With tool use, thinking blocks **must** be returned verbatim in the next assistant message — the loop already records assistant `content` as-is, which satisfies this. Do not strip thinking blocks when persisting/replaying history.
  - Thinking shows once per turn (before the first response), not before each tool retry. Reasoning between tool calls would need interleaved thinking — beta header `anthropic-beta: interleaved-thinking-2025-05-14` (not currently enabled).
- **Retry:** transient failures (429 / 5xx / 529 "Overloaded") retry up to 4 attempts with exponential backoff (~1s/2s/4s), honoring `Retry-After`. Permanent errors (auth, bad request) fail immediately.

### 5.2 JSearch (RapidAPI)
- Endpoint: `https://jsearch.p.rapidapi.com/search`
- Headers: `x-rapidapi-key`, `x-rapidapi-host: jsearch.p.rapidapi.com`
- Free tier: 200 req/month — cache aggressively in Firestore `jobs/`
- Key: `--dart-define=RAPIDAPI_KEY=...`

### 5.3 Gmail API (Google)
- Use the existing Google Sign-In credential, add scope `https://www.googleapis.com/auth/gmail.send`
- Package: `googleapis` + `googleapis_auth` (add to pubspec)
- Send via `users.messages.send` with a base64-encoded MIME message
- Attachments: PDF resume as `application/pdf` part

### 5.4 Hunter.io (optional, stretch)
- Endpoint: `https://api.hunter.io/v2/domain-search`
- Free tier: 25 searches/month
- Key: `--dart-define=HUNTER_API_KEY=...`
- Skip if quota is risky; fall back to `careers@{company}.com` guess in `draft_email`

---

## 6. Security & rules

### `firestore.rules` (deployed)
- `jobs/{jobId}` — any signed-in user read/write
- `users/{uid}/**` — owner-only

### Secrets posture for v1 demo
- API keys ship in the client (compiled in via `--dart-define`).
- **Rotate every key after the demo.** Set spend caps in each provider's console.
- Production-grade key management is explicitly out of scope (would require a server).

---

## 7. PDF template (fixed)

Classic single-column, ATS-safe, black-on-white. ASCII mockup:

```
DARYN WELLING                                                ← 24pt bold center
daryn@example.com  ·  +60 12-345-6789  ·  linkedin.com/in/daryn   ← 9pt center

SUMMARY                                                       ← 11pt bold uppercase
Product-focused engineer with 4 years building consumer mobile apps.

EXPERIENCE
Acme Corp — Senior Engineer                       Jan 2024 – Present
  • Shipped feature X to 200K users; cut p95 latency 40%.
  • Led migration to Flutter, halving build time.

EDUCATION
NTU Singapore — BEng Computer Science                     2018 – 2022

SKILLS
Flutter · Dart · Firebase · TypeScript · Python
```

Built once in `lib/features/resumes/services/pdf_template.dart` via `pw.Document`.
Page-overflow rule: allow page 2 if experience is long; no graphics ever.

---

## 8. Rate limits & cost guards

| Surface | Cap | Why |
|---|---|---|
| `search_jobs` (JSearch) | Cache results in `jobs/` for 1 hour | Stay under 200 calls/month |
| `match_jobs` | Max 25 jobs per call | Anthropic latency |
| `tailor_resume` | One in-flight per session | Anthropic spend |
| `lookup_hiring_manager` | Cache by company for 24h | Hunter quota |
| `send_email` | Hard-blocked without user tap | Trust |
| Anthropic monthly | Set $5 spend cap in console | Demo safety |

---

## 9. In scope additions and out-of-scope clarifications

### In scope (added in v1.1 brainstorm)

**In-app notifications inbox** — when the user leaves the chat while the
agent is mid-loop, agent events (especially `ask_user` and tool-completion
results) land in [lib/features/notifications/](../lib/features/notifications/)
as actionable items. From the notifications page the user can accept, edit, or
answer follow-up questions inline — same surfaces as the chat would have shown.
The agent loop continues in the background regardless of which screen the user
is on. **This is the walk-away pattern.** Owner: FE2 (UI) + B3 (event routing).

**Applications page** — replaces the v1.0 separate "Tracker" + "History"
concepts. One page, status filters, sorted in-flight first. Lives at
[lib/features/applications/](../lib/features/applications/).

### Out of scope for v1

- *Push* notifications (FCM) — in-app inbox only; no system tray.
- Cross-device resume sync (PDFs are local-cache).
- Auto-submit applications.
- LinkedIn integration.
- Cover-letter generation as a separate document.
- Chat persistence (in-memory only).
- Multi-account Gmail.
- Calendar API integration for interview scheduling.

---

## 10. Migration / build status

| Piece | Status | Owner (see [team-handoff.md](./team-handoff.md)) |
|---|---|---|
| Firebase Auth + Google Sign-In | ✅ Done | Track E |
| Firestore + rules deployed | ✅ Done | Track E |
| User doc creation on sign-in | ✅ Done | Track E |
| Tracker on Firestore (streaming) | ✅ Done | Track D |
| Pipeline cards on Firestore | ✅ Done | Track C |
| Brief reasoner → Anthropic + Firestore | ✅ Done | Track A |
| Agent chat → direct Anthropic | ✅ Done | Track A |
| Pipeline approve → application | ✅ Done | Track D |
| Resume upload | ⚠️ Has Firebase Storage; **swap to local-cache** | Track B |
| Tool registry + executor | ❌ Not built | Track A |
| `InputRequestBlock` + ask_user UI | ❌ Not built | Track A |
| Resume parser (lazy) | ❌ Not built | Track B |
| Resume tailor service | ❌ Not built | Track B |
| Fixed PDF template | ❌ Not built | Track B |
| JSearch direct from Flutter | ❌ Not built | Track C |
| Gmail API send | ❌ Not built | Track D |
| Hunter.io lookup (stretch) | ❌ Not built | Track C |
| `backend/` Python dir | ⚠️ Delete after demo | — |
| **v1.3 changes** | | |
| `ProposedEdit` model + `resume_diff_service` | ❌ Not built | B1 |
| `tailor_resume` returns proposed_edits (not PDF) | ❌ Not built | B1 + B3 |
| `apply_resume_edits` tool | ❌ Not built | B1 |
| `ProposedEditsBlock` (PR-style review, inline in chat) | ❌ Not built | FE2 / R2 |
| Riverpod migration + immutable state | ✅ Shipped 2026-05-18 (see §1.5) | FE1 |
| Remove 24h auto-fire from PassiveAgentController | ✅ No timer exists; `runBrief()` is a pure callable | B3 (verified) |
| "Run today's brief" dashboard CTA | ✅ Shipped 2026-05-18 — `_RunBriefCta` in [dashboard_page.dart](../lib/features/dashboard/presentation/dashboard_page.dart) | FE1 |
| Dashboard prompt entry dispatches text to chat | ✅ Shipped 2026-05-18 | FE1 |
| `morning_brief_enabled` setting + toggle in Settings | ✅ Shipped 2026-05-18 — Settings page section gates dashboard CTA via `userProfileProvider` | FE1 |
| Settings page (autonomy slider + brief toggle + delete account) | ✅ Shipped 2026-05-18 | FE1 |
| `UserRepository.update()` partial-update | ✅ Shipped 2026-05-18 | FE1 |
| Onboarding actually captures + persists `role` via `userProfileProvider` | ✅ Shipped 2026-05-18 — router redirect sends new users (role=null) to `/onboarding` once | FE1 |

---

## 11. Open questions (need a call before coding)

1. **One-page PDF hard limit, or allow overflow to page 2?** — recommend allow overflow.
2. **Tailor input** — feed Claude the pipeline card's `why` summary, or the full `jobs/{id}.description`? — recommend full description.
3. **Parse-failure UX** — if Claude returns malformed JSON for `read_resume`, retry once then surface error? — recommend yes.
4. **Cascade-delete** — deleting a manual resume: delete tailored children too, or orphan them? — recommend cascade.
5. **Gmail scope** — `gmail.send` only (write-only), or also `gmail.readonly` for reply tracking? — recommend send-only for v1.

Lock these into §0 once answered.
