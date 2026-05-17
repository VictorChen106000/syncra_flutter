# Syncra Architecture Contract

**Status:** Draft v1.1 — agent-first reframe, replaces v0.4 REST contract
**Demo target:** June 16, 2026
**Last updated:** 2026-05-16

Single source of truth for how Syncra is wired. If code disagrees with this
file, this file wins. Product context lives in [product-brief.md](./product-brief.md);
team ownership in [team-plan.md](./team-plan.md). Old v0.4 contract archived at
[api-contract-v0.4-archived.md](./api-contract-v0.4-archived.md).

---

## 0. Locked decisions (don't re-litigate)

| Decision | Choice |
|---|---|
| App platform | Flutter (iOS / Android / Web) |
| Server | **None.** No FastAPI, no Cloud Functions. |
| Auth | Firebase Auth — Google Sign-In only |
| Database | Cloud Firestore (Spark plan) |
| File storage | **Local device** via `path_provider`. No Firebase Cloud Storage. |
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

## 1. Agent loop — the primary UX

There is **one** agent. What looks like "passive" vs "active" agent in the UI
is just two **triggers** for the same `AnthropicChatService.runAgent` loop:

- **User trigger** — user types a prompt; chat shows the tool calls live.
- **System trigger** — when the user opens the app and `users/{uid}.last_brief_at`
  is null or > 24h old, [PassiveAgentController](../lib/features/agent/state/passive_agent_controller.dart)
  fires a canned prompt (*"Find 5 fresh jobs matching my profile, score them
  via match_jobs, and save each as a pipeline card via save_to_pipeline"*).
  Same code path, same tools. The user sees tool-call progress in the
  notifications inbox; cards land on the pipeline page.

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
| `tailor_resume` | ✅ | User reviews the PDF before save |
| `draft_email` | ✅ | User reviews before send |
| `lookup_hiring_manager` | ✅ | No |
| `save_to_tracker` | Depends on `autonomy_level` | Writes to the Applications page. `suggest` → ask; `auto_apply` → just do it |
| `send_email` | ❌ | **Always requires user tap.** No exceptions in v1. |
| `ask_user` | n/a | Paused, awaits user typing |

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
description: Rewrite the user's resume for a specific job. Returns a new tailored ResumeJSON.
input_schema:
  resume_id: string
  job_id: string
backed_by: Anthropic (paraphrase only — never invents experience)
returns: { tailored_resume_id, resume_json }
side_effect: renders to PDF, saves to local disk, creates new Firestore resume doc with source='tailored'
requires_confirmation: false (user reviews preview before next step)
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
| Field | Type |
|---|---|
| `name`, `email`, `avatar_url`, `role` | string(?) |
| `is_agent_active` | bool |
| `autonomy_level` | `'suggest' \| 'ask_first' \| 'auto_apply'` |
| `gmail_connected` | bool |
| `gmail_refresh_token` | string? (encrypted; v2) |
| `created_at`, `last_brief_at` | Timestamp |

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

| Piece | Status | Owner (see team-plan.md) |
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

---

## 11. Open questions (need a call before coding)

1. **One-page PDF hard limit, or allow overflow to page 2?** — recommend allow overflow.
2. **Tailor input** — feed Claude the pipeline card's `why` summary, or the full `jobs/{id}.description`? — recommend full description.
3. **Parse-failure UX** — if Claude returns malformed JSON for `read_resume`, retry once then surface error? — recommend yes.
4. **Cascade-delete** — deleting a manual resume: delete tailored children too, or orphan them? — recommend cascade.
5. **Gmail scope** — `gmail.send` only (write-only), or also `gmail.readonly` for reply tracking? — recommend send-only for v1.

Lock these into §0 once answered.
