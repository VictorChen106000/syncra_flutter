# Syncra — Team Handoff Packet

**For:** the 5-person team (3 backend + 2 frontend)
**Demo day:** June 16, 2026 (~30 days out)
**Last updated:** 2026-05-16

This is the single doc your team needs. Print it, export it to PDF
(VSCode → "Markdown PDF" extension or Typora), share it however you want.

If you want the *why* behind decisions, read [product-brief.md](./product-brief.md).
If you want the *spec*, read [api-contract.md](./api-contract.md).
This doc is the *how* — who does what, where the files live, and in what order.

---

## 1. Five-minute overview

### What Syncra is

An AI career copilot inside a Flutter app. User says *"help me apply to a UX role
at an AI startup"* — the agent searches jobs, reads the user's resume, tailors it
for the best match, drafts an email, and lines it up for one tap to send. The user
reviews and approves at every decision point.

### Locked stack — don't change without team vote

- **Flutter** (iOS / Android / Web) — the entire app
- **Firebase Auth** + **Cloud Firestore** (Spark / free plan, no credit card)
- **Anthropic Claude** (Haiku 4.5) — agent brain, called directly from Flutter
- **JSearch via RapidAPI** — live job listings
- **Gmail API** — send drafted emails from the user's own Gmail
- **Hunter.io** *(optional, stretch)* — find hiring-manager emails

**No backend server.** No FastAPI, no Cloud Functions. Course rule — Flutter +
Firebase only. The Python backend is gone (folder kept on disk until demo for
reference; delete after).

### Current state — what's already shipped

| Already done — don't redo | Status |
|---|---|
| Google Sign-In via Firebase Auth | ✅ |
| Firestore migration (users / applications / pipeline / resumes / jobs) | ✅ |
| Owner-only Firestore security rules deployed | ✅ |
| Anthropic chat with full tool-use loop | ✅ |
| `ask_user` mid-flow input (text field in chat) | ✅ |
| Tool registry + 8 tools registered | ✅ (some stubs, some real) |
| Resume upload via `path_provider` (local file + Firestore metadata) | ✅ |
| PDF text extraction (`syncfusion_flutter_pdf`) | ✅ |
| Resume parser (PDF text → Claude → ResumeJSON, lazy + cached) | ✅ |
| Resume tailor service + fixed PDF template | ✅ |
| Tailor orchestrator (parse → tailor → render → save) | ✅ |
| Tracker streaming from Firestore, status updates, notes | ✅ |
| Brief reasoner client-side (writes pipeline cards to Firestore) | ✅ |
| Pipeline approve → creates entry on Applications page | ✅ |

If you find yourself building one of these from scratch, **stop and ask** — it
probably already exists.

---

## 2. Day-one setup

### Accounts to create (free, no card)

| Service | Purpose | Where |
|---|---|---|
| Anthropic API | Claude key | https://console.anthropic.com → API Keys |
| RapidAPI | JSearch key (200 req/month free) | https://rapidapi.com/letscrape-6bRBa3QguO5/api/jsearch |
| Google Cloud | Gmail API scope on existing Firebase project | https://console.cloud.google.com → APIs & Services → Library → "Gmail API" → Enable |
| Hunter.io *(stretch)* | 25 free domain searches/month | https://hunter.io → Sign Up |

Set monthly spend caps wherever you can. Anthropic has it in the console under
"Spend limits". Set yours to **$5/month** for safety.

### Running the app locally

```bash
git clone <repo>
cd syncra_flutter
flutter pub get
flutter run \
  --dart-define=ANTHROPIC_API_KEY=sk-ant-... \
  --dart-define=RAPIDAPI_KEY=...           # add when Track 2 needs it \
  --dart-define=HUNTER_API_KEY=...         # optional, Track 2 stretch
```

### Verify the app boots

After `flutter run`:
1. Sign in with Google.
2. Open Firebase Console → Firestore → you should see your `users/{uid}` doc.
3. Tap the chat icon → type *"I want to apply somewhere good"* → Claude should
   call `ask_user` and a text field appears in the chat.

If any of that fails, post in the team chat with the error before changing code.

---

## 3. Folder structure (with status per area)

Legend: ✅ done · 🟡 stub/partial · ⏳ todo · (T#) which track owns it

```
syncra_flutter/
├── docs/
│   ├── product-brief.md              ✅ — what Syncra is
│   ├── api-contract.md               ✅ — data model + tools spec
│   ├── team-plan.md                  ✅ — older 5-track plan (overlap w/ this doc)
│   └── team-handoff.md               ← you are here
│
├── firebase.json, firestore.rules    ✅ — deployed, don't edit without team vote
│
├── lib/
│   ├── main.dart, app.dart           ✅ — provider tree, router boot   (FE1)
│   │
│   ├── core/
│   │   ├── constants/                ✅ — colors, strings, sizes      (FE1)
│   │   ├── router/                   ✅ — go_router config             (FE1)
│   │   └── theme/                    ✅                                (FE1)
│   │
│   ├── data/
│   │   ├── firestore/
│   │   │   ├── firestore_paths.dart      ✅
│   │   │   ├── user_repository.dart      ✅ 🟡 needs an update() method (FE1)
│   │   │   ├── applications_repository.dart ✅
│   │   │   ├── pipeline_repository.dart  ✅
│   │   │   ├── jobs_repository.dart      ✅
│   │   │   └── resumes_repository.dart   ✅ — local-cache via path_provider  (B1)
│   │   └── models/
│   │       ├── job.dart, tracked_application.dart  ✅
│   │
│   ├── fixtures/                     ✅ — dev-only sample data (was data/mock/)
│   │
│   ├── features/
│   │   ├── agent/
│   │   │   ├── services/anthropic_service.dart  ✅ — brief reasoner   (B3)
│   │   │   ├── state/passive_agent_controller.dart  ✅                (B3)
│   │   │   └── data/fake_resume.dart  ✅ — fallback ResumeJSON
│   │   │
│   │   ├── agent_chat/               ← Track B3's home
│   │   │   ├── models/
│   │   │   │   ├── agent_block.dart  ✅ — Text/Thinking/Tool/InputRequest blocks
│   │   │   │   └── chat_message.dart ✅
│   │   │   ├── services/
│   │   │   │   ├── agent_service.dart           ✅ — interface
│   │   │   │   └── anthropic_chat_service.dart  ✅ — tool-use loop    (B3)
│   │   │   ├── state/agent_chat_controller.dart ✅                    (B3)
│   │   │   ├── tools/
│   │   │   │   ├── tool.dart, tool_registry.dart       ✅
│   │   │   │   ├── anthropic_tool_calls.dart    ✅ — paraphrase + draft (B3)
│   │   │   │   └── builtin_tools.dart           🟡 — see Track briefs (B2/B3)
│   │   │   └── presentation/widgets/agent_block_views.dart  🟡 — InputRequestView done, decision cards todo (FE2)
│   │   │
│   │   ├── auth/                     ✅ — sign-in works, onboarding TODO (FE1)
│   │   │   ├── presentation/
│   │   │   │   ├── login_page.dart       ✅
│   │   │   │   ├── splash_page.dart      ✅
│   │   │   │   ├── signup_page.dart      ✅
│   │   │   │   ├── onboarding_page.dart  🟡 — needs autonomy_level capture (FE1)
│   │   │   │   └── morning_brief_page.dart ✅
│   │   │   ├── services/google_auth_service.dart  ✅
│   │   │   └── state/auth_controller.dart  ✅
│   │   │
│   │   ├── dashboard/                🟡 — needs prominent prompt entry (FE1)
│   │   ├── profile/                  🟡 — bare scaffold, needs settings (FE1)
│   │   ├── notifications/            🟡 — needs in-app agent-event inbox + inline actions (FE2)
│   │   ├── applications/             ✅ — streaming, status, notes (was tracker/) (FE1 polish)
│   │   │
│   │   ├── jobs/
│   │   │   ├── state/jobs_controller.dart  ✅ — pipeline stream + approve
│   │   │   └── presentation/
│   │   │       ├── jobs_page.dart    ✅
│   │   │       ├── job_detail_page.dart ✅
│   │   │       ├── tailor_page.dart  🟡 — wire to real tailor flow    (FE2)
│   │   │       ├── review_page.dart  ✅ — approve hooks done
│   │   │       └── submitted_page.dart ✅
│   │   │
│   │   ├── resumes/                  ← Track B1's home
│   │   │   ├── models/
│   │   │   │   ├── resume_file.dart      ✅
│   │   │   │   ├── resume_json.dart      ✅ — structured form
│   │   │   │   └── upload_queue_item.dart ✅
│   │   │   ├── services/
│   │   │   │   ├── pdf_text_extractor.dart       ✅
│   │   │   │   ├── resume_parser_service.dart    ✅ — lazy parse
│   │   │   │   ├── resume_tailor_service.dart    ✅
│   │   │   │   ├── pdf_template.dart             ✅ — fixed layout
│   │   │   │   └── resume_tailor_orchestrator.dart  ✅ — full chain  (B1)
│   │   │   ├── state/resume_controller.dart  ✅ — local-cache wired
│   │   │   └── presentation/
│   │   │       ├── resume_lists_page.dart  ✅
│   │   │       ├── resume_preview_page.dart ✅ — local file viewer
│   │   │       └── widgets/                 ✅
│   │   │
│   │   └── email/                    ⏳ — does not exist yet, create  (FE2 + B2)
│   │       ├── services/             (B2 — Gmail API client)
│   │       └── presentation/email_review_page.dart (FE2 — review modal)
│   │
│   └── shared/widgets/               ✅ — design-system primitives (FE1)
│
├── pubspec.yaml                      ✅ — locked deps, see "PR rules"
└── backend/                          ⚠️ — DELETE after demo. Don't add code here.
```

---

## 4. The five tracks

Each brief has the same shape:
- **You own** — files and concerns
- **Why it matters** — the user-facing thing your work unlocks
- **Build order** — what to do first vs. later
- **You're done when** — concrete acceptance criteria
- **Dependencies** — what blocks you / what you'd block
- **Common pitfalls** — things to avoid

Pick a track in the team chat. First-come, first-served. The 5th person
(probably the team lead — that's you, the person who handed out this packet)
takes whatever isn't claimed plus the integrator role.

---

### Track 1 — Backend: Resume Pipeline (B1)

**You own**
- [lib/features/resumes/](../lib/features/resumes/) — every service, model, repository
- [lib/data/firestore/resumes_repository.dart](../lib/data/firestore/resumes_repository.dart)
- The `read_resume` and `tailor_resume` tool implementations in [builtin_tools.dart](../lib/features/agent_chat/tools/builtin_tools.dart) (~lines 122-400)

**Why it matters**
The "tailor my resume for this job" loop is the headline demo moment. Your code
takes a real PDF the user uploaded, extracts the text, asks Claude to rewrite
bullets emphasizing the right keywords, and renders a new PDF through our fixed
template. Without it, the agent can talk about resumes but can't produce one.

**Build order**
1. **Verify the existing pipeline end-to-end** — upload a real PDF resume, then
   open the chat and ask the agent to tailor it for one of the seeded jobs.
   Watch the orchestrator run. Fix anything that breaks.
2. **Scanned-PDF edge case** — if `PdfTextExtractor` returns an empty string,
   surface a friendly "this PDF looks like a scan — please upload a text PDF"
   error to the chat instead of falling back to the sample resume.
3. **Parser retry** — if Claude returns malformed JSON for `parseResume`,
   retry once with a stricter prompt before giving up. (~10 lines in
   [resume_parser_service.dart](../lib/features/resumes/services/resume_parser_service.dart))
4. **Cascade-delete tailored resumes** — when the user deletes a manual resume,
   also delete its tailored children. Wire up in `ResumeController.deleteResume`.
5. **(Stretch)** A "Tailor history" UI showing original PDF + each tailored
   variant grouped together on the resume list page.

**You're done when**
- Upload a real resume → tap a "ready" pipeline card → review_page → approve →
  a tailored PDF appears in the resume list within ~15 seconds.
- Opening that tailored PDF shows real bullets emphasizing the target job's
  keywords, in the fixed template.
- Deleting the parent resume cleans up tailored children too.

**Dependencies**
- None blocking — the foundation is in place.
- Other tracks depend on you for `read_resume` / `tailor_resume` to actually
  work end-to-end.

**Common pitfalls**
- Don't add `firebase_storage` back. Local-cache only.
- Don't change the PDF template layout without team vote — consistency is a feature.
- Don't add new fields to `resume_json` without updating [api-contract.md §2.4](./api-contract.md).

---

### Track 2 — Backend: API Fetch (B2)

**You own**
- `lib/data/services/jsearch_service.dart` — **create this**
- `lib/data/services/hunter_service.dart` — **create this** *(stretch)*
- The `search_jobs` and `lookup_hiring_manager` tool implementations in
  [builtin_tools.dart](../lib/features/agent_chat/tools/builtin_tools.dart)
- `lib/features/email/services/gmail_service.dart` — **create this** *(send only,
  not draft — drafting is B3's territory in `anthropic_tool_calls.dart`)*

**Why it matters**
Right now `search_jobs` reads pre-seeded data from the `jobs/` Firestore
collection — about 10 jobs from old test data. For a real demo, the agent needs
fresh listings. You wire JSearch (live job-board aggregator) and cache results
in `jobs/` so we stay under the 200 req/month free quota.

You also wire the **actual sending** of emails through Gmail — the agent has
been drafting fake emails until now.

**Build order**
1. **JSearch service** — direct HTTP call to RapidAPI. Port the logic from the
   old `backend/app/jobs/sources.py` (it's already proven against the JSearch
   schema — translate from Python to Dart). Upsert results into `jobs/` with
   the same deterministic ID scheme.
2. **In-memory cache** — `(query, location) → results` keyed for 1 hour to
   stay under quota.
3. **Replace `search_jobs` tool handler** — instead of `repo.fetchAll(40)`,
   call `jsearchService.search(query, location, limit)`. Keep the result
   shape identical so Claude's downstream tool calls don't change.
4. **Gmail service** — use `googleapis` + `googleapis_auth` packages (add to
   pubspec). Build a MIME message with optional PDF attachment. Post to
   `users.messages.send`. The OAuth scope `gmail.send` must be added to the
   existing Google Sign-In config (coordinate with FE1).
5. **Replace `send_email` tool handler** — gate the actual send behind FE2's
   review modal (see Track FE2). The tool itself should refuse to send unless
   the modal passed an explicit `confirmed: true` flag.
6. **(Stretch) Hunter.io** — single endpoint, finds emails by company domain.
   Cache by company for 24 hours. Wire into `lookup_hiring_manager`.

**You're done when**
- Type *"find UX designer jobs in Singapore"* in chat → real, current Singapore
  listings come back (not the seeded data).
- After FE2's review modal lands: tap "Send" → email actually arrives in the
  recipient's inbox, with the tailored PDF attached, from the user's Gmail.

**Dependencies**
- **You depend on FE2** for the review modal that gates `send_email`. Coordinate
  on the confirmation handshake (e.g. a `confirmation_token` argument).
- **You depend on FE1** for adding the `gmail.send` OAuth scope to Google Sign-In.

**Common pitfalls**
- JSearch returns a *lot* of data per result. Trim before storing in `jobs/` —
  no need to keep 10 KB descriptions, 240-char excerpts are plenty.
- Don't cache by raw URL — JSearch sometimes returns the same job with two
  different `job_apply_link` values. Use the existing `_jobIdFor()` hash logic
  from the old Python code.
- Gmail's `gmail.send` scope requires app verification eventually, but
  unverified-app warnings are fine for a class demo. Tell the TA this in
  advance so they aren't surprised.
- Never log API keys.

---

### Track 3 — Backend: Agent Reasoning (B3)

**You own**
- [lib/features/agent_chat/services/anthropic_chat_service.dart](../lib/features/agent_chat/services/anthropic_chat_service.dart) — the tool-use loop
- [lib/features/agent_chat/tools/anthropic_tool_calls.dart](../lib/features/agent_chat/tools/anthropic_tool_calls.dart) — paraphrase + draft email prompts
- [lib/features/agent_chat/tools/builtin_tools.dart](../lib/features/agent_chat/tools/builtin_tools.dart) — system prompt + tool descriptions (the "personality")
- [lib/features/agent/services/anthropic_service.dart](../lib/features/agent/services/anthropic_service.dart) — brief reasoner / job matcher
- [lib/features/agent/state/passive_agent_controller.dart](../lib/features/agent/state/passive_agent_controller.dart) — brief lifecycle

**Why it matters**
The loop works — but how *well* it works depends on prompt quality, tool
description clarity, and how the agent handles edge cases (ambiguous user
intent, partial tool failures, hitting the loop limit). The difference between
"impressive demo" and "hung up agent" lives in your code.

**Build order**
1. **Run 10 demo prompts end-to-end** with the current setup. Log every Claude
   turn (tool calls, text). Identify failure patterns.
2. **Tune the system prompt** in `anthropic_chat_service.dart` (constant `_system`).
   Right now it's basic — make it teach Claude to *prefer* calling tools over
   guessing, and to use `ask_user` when stuck.
3. **Tune tool descriptions** in `builtin_tools.dart`. Each tool's `description:`
   is what Claude reads when picking. Make them tight, behavioral, and clear
   about when *not* to use the tool.
4. **Improve `ask_user` UX from the agent side** — when the agent calls
   `ask_user`, often it should also provide 2-3 suggestions. Bake that into the
   tool description ("Always provide 2-3 suggestions unless the question is
   genuinely open-ended").
5. **Loop safety nets** — current limit is 8 iterations. Add better recovery
   messages when the loop terminates because of repeated tool failures (not
   just iteration cap).
6. **Brief reasoner quality** — tune the `_systemPrompt` in `anthropic_service.dart`
   so categorizations are sharper (fewer "exploration" defaults).
7. **NEW: implement `save_to_pipeline` tool** in [builtin_tools.dart](../lib/features/agent_chat/tools/builtin_tools.dart) — see [api-contract.md §2.6b](./api-contract.md). Lets the agent persist pipeline cards instead of `PassiveAgentController` bypassing the tool registry.
7a. **NEW: implement `remember_fact` tool** + `users/{uid}/learned_facts/`
    collection — see [api-contract.md §2.6a](./api-contract.md). When the user
    answers an `ask_user`, the agent persists the answer. Future tailoring
    reads `learned_facts` via `read_resume` (extend that tool to include them).
    Strong demo moment: "the agent learns about you across sessions." ~3h.
8. **NEW: refactor `PassiveAgentController.runBrief()`** to call
   `AnthropicChatService.runAgent` with a canned brief prompt instead of
   calling `AnthropicService.scoreJobs` directly. This locks in the "one agent,
   two triggers" model (see [api-contract.md §1](./api-contract.md)). ~2-3h.
9. **Event-stream subscription** for FE2's notifications inbox — expose the
   agent's event stream above the chat controller so both the chat UI and the
   notifications page can subscribe.

**You're done when**
- Vague prompts ("help me find a job") trigger appropriate `ask_user` calls
  with helpful suggestion chips, not random tool fires.
- Specific prompts ("apply to a UX role at Linear using my latest resume")
  produce the full chain — search → read_resume → match → tailor → draft —
  with minimal user friction.
- When a tool fails (e.g. JSearch returns 0 results), the agent acknowledges
  cleanly and asks the user what to try next, instead of looping or going silent.

**Dependencies**
- You depend on B1 + B2 for the underlying tools to actually do real work.
- FE2 surfaces your output, so coordinate with them on what the `text` blocks
  look like (avoid markdown if FE2 hasn't shipped markdown support yet — they
  haven't).

**Common pitfalls**
- Don't tune by feel alone — keep a list of 10 canonical demo prompts and
  test each prompt before and after every prompt change.
- Don't add new tools without updating [api-contract.md §2](./api-contract.md).
- Don't increase `_maxLoopIterations` past 10 without thinking about cost.

---

### Track 4 — Frontend: Shell & Onboarding (FE1)

**You own**
- [lib/core/router/](../lib/core/router/) — navigation
- [lib/app.dart](../lib/app.dart) — provider tree (touch carefully — coordinate
  with B3 when adding new controllers)
- [lib/features/auth/](../lib/features/auth/) — sign-in, splash, onboarding
- [lib/features/dashboard/](../lib/features/dashboard/) — landing screen
- [lib/features/profile/](../lib/features/profile/) — needs to become a real settings page
- [lib/features/applications/presentation/](../lib/features/applications/presentation/) — Applications UI (was tracker, mostly done, may need polish)
- [lib/shared/widgets/](../lib/shared/widgets/) — design system
- Build configuration — `--dart-define` recipes, README setup section
- Firebase project config — when Track 2 adds Gmail scope, you coordinate

**Why it matters**
The shell is what makes the app feel like a *product* and not a demo. Empty
states, smooth navigation, consistent typography, a clear onboarding that
captures the user's preferences (autonomy level, role) — that's all you. The
agent is the headline, but the shell is what people feel.

**Build order**
1. **Onboarding capture** — add screens that capture `autonomy_level`
   (`'suggest' | 'ask_first' | 'auto_apply'`) and `role` (free-text e.g. "Senior
   UX Designer"). Persist both to `users/{uid}` via `UserRepository.update`
   (you may need to add a method). The brief reasoner already reads `role`.
2. **Dashboard prompt entry** — a prominent "What would you like the agent to
   do?" input on the dashboard that deep-links to the chat with the message
   pre-filled. This is the agent's main entry point.
3. **Settings page** — replace [lib/features/profile/presentation/profile_page.dart](../lib/features/profile/presentation/profile_page.dart)
   with a real settings page: autonomy slider, sign out, delete account.
4. **Empty states** everywhere — first-time user with no resume, no jobs in
   pipeline, no applications on the Applications page. Each empty state should explain how
   to get started AND offer a one-tap action (e.g. "Open the chat").
4a. **NEW: Activity-log refactor of the Applications page.** Drop the
    multi-stage status enum (viewed/replied/interview/offer/rejected) — see
    [api-contract.md §3](./api-contract.md). New fields: `drafted_at`,
    `sent_at`, `got_reply` (user-flippable bool), `follow_up_at`, `notes`.
    Rebuild [applications_page.dart](../lib/features/applications/presentation/applications_page.dart)
    to render as a date-sorted activity log with a "Got a reply" switch on each
    entry. Filter chips become `All / Drafts / Sent / Replied`. Coordinate with
    [ApplicationsController](../lib/features/applications/state/applications_controller.dart) +
    [ApplicationsRepository](../lib/data/firestore/applications_repository.dart). ~4-5h.
5. **Build config doc** — a README section listing every `--dart-define` flag,
   where each key comes from, and a single `flutter run` command that has them
   all. Save your friends 30 minutes each.
6. **Polish loop** — animations, snackbar consistency, error styling. Bug-bash
   week.

**You're done when**
- A brand new user can: sign in → onboard → land on dashboard with a prompt
  entry → tap chat → see the agent ask a sensible first question.
- Settings page exists, autonomy is editable, sign out works on all platforms.
- Every screen with a list has a beautiful empty state.
- README has a working "how to run this app" section.

**Dependencies**
- Coordinate with B2 on adding the Gmail OAuth scope to Google Sign-In config.
- Coordinate with FE2 on consistent navigation patterns (back buttons, modals).

**Common pitfalls**
- Don't restructure the provider tree without checking with B3 — the chat
  controller has subtle dependencies on AuthController and ResumeController
  being created before it.
- Don't break the `go_router` redirect logic — it handles auth-gating.
- Don't add a new top-level dependency without team vote.

---

### Track 5 — Frontend: Agent Surfaces, Email, & Notifications Inbox (FE2)

**You own**
- [lib/features/agent_chat/presentation/](../lib/features/agent_chat/presentation/) — chat UI polish
- [lib/features/agent_chat/presentation/widgets/agent_block_views.dart](../lib/features/agent_chat/presentation/widgets/agent_block_views.dart) — block renderers
- [lib/features/resumes/presentation/](../lib/features/resumes/presentation/) — resume list / preview / tailor flow
- [lib/features/jobs/presentation/tailor_page.dart](../lib/features/jobs/presentation/tailor_page.dart) — wire to real tailor
- [lib/features/notifications/](../lib/features/notifications/) — **upgrade from static list to in-app agent-event inbox** with inline actions (the walk-away feature)
- `lib/features/email/presentation/email_review_page.dart` — **create this**

**Why it matters**
Whatever the agent does, the user sees through the chat. If the chat looks
janky, the agent feels janky. Your job is to make each tool block, each
`ask_user` prompt, each accept-or-edit decision card feel *crafted*.

Plus you build the **two pieces of UI that gate critical actions**:
- The **email review modal** — without it, B2 can't ship `send_email` safely.
- The **notifications inbox** — without it, the user is trapped inside the chat
  while the agent works. The inbox is what makes the "walk away, get
  notified, accept from there" pattern work.

**The notifications inbox in detail.** When the agent fires an `ask_user` or
finishes a tool call (`tailor_resume` produces a new PDF, `draft_email` produces
a draft to review), an entry lands in the notifications page. Each entry shows
the same surface the chat would have shown (text field, accept/edit buttons,
preview card). Tapping it acts inline; the agent loop continues. This requires
coordination with B3 — agree on an `AgentEvent`-stream subscription that lives
above the chat controller so both UIs can observe it.

**Build order**
1. **`InputRequestView` polish** — it works but isn't pretty. Make the text
   field expansion smooth, suggestion chips beautiful, "answered" state
   distinct.
2. **Decision cards on tool results** — when the agent tailors a resume and
   `tool_use` returns `{ tailored_resume_id, file_name }`, render an
   `ActionProposalBlock`-like card showing "Tailored {file} — Preview / Save /
   Discard". Wire to the chat controller.
3. **Notifications inbox upgrade** — the existing `notifications/` page is a
   static list of fixtures. Rewrite it as a live subscription on the agent's
   event stream. Each agent `ask_user` and tool completion that happens while
   the user isn't on the chat page becomes a notification entry. Tapping an
   entry shows the inline surface (text field or decision card) right there —
   no jump to chat required. Coordinate with B3 on the subscription shape.
4. **Email review modal** — the most important send-gate. Modal sheet with
   subject + body (both editable), "Send to {recipient}" button. Tap the
   button → `JobsController.confirmAndSendEmail(token)` → triggers B2's
   `send_email` tool with a confirmation token. Coordinate with B2 on the
   token shape.
5. **Resume preview improvements** — when the local file is missing (different
   device), show a clear "this resume isn't on this device" state with a
   re-upload button.
6. **Tailor flow page** — wire `tailor_page.dart` to call the real tailor
   tool (via the controller, not the agent loop directly). Show progress
   states: "extracting text", "tailoring", "rendering PDF".
7. **Cross-platform check** — run on iOS, Android, web. Note differences in
   a shared doc, file issues against FE1 for any shell-layer bugs you find.

**You're done when**
- The chat looks beautiful — `ask_user`, tool blocks, decision cards all feel
  consistent.
- The user can close the chat mid-loop → see a notification entry appear →
  tap it → answer or accept inline → agent continues without re-opening chat.
- The email review modal exists, is editable, and the send button is the
  *only* path to actually sending an email.
- The tailor flow page works without going through the chat.
- App looks correct on iOS and Android.

**Dependencies**
- B3 controls what blocks the agent emits — coordinate on new block types.
- B2 controls when `send_email` actually fires — coordinate on the confirmation
  handshake (suggestion: a one-shot UUID generated by the modal, passed to the
  tool, validated on the receiving side).

**Common pitfalls**
- Don't add markdown rendering to text blocks unless B3 says the agent will
  emit markdown. Right now it doesn't.
- Don't bypass the review modal for `send_email` — the whole point of that
  modal is "the user explicitly tapped Send."
- Don't fork the design-system widgets — extend the ones in `lib/shared/widgets/`.

---

## 5. PR + collaboration rules

### Branch per track
Each track has its own branch off `main`. Name them: `b1-resumes`, `b2-apis`,
`b3-agent`, `fe1-shell`, `fe2-surfaces`. Merge to main via PR. Squash on merge.

### PR review
- **B1, B2, B3 PRs** — reviewed by another backend person.
- **FE1, FE2 PRs** — reviewed by the other frontend person.
- **Anything touching [app.dart](../lib/app.dart) or [pubspec.yaml](../pubspec.yaml)** — reviewed by FE1 (they own build config).
- **Anything touching [api-contract.md](./api-contract.md)** — reviewed by 2+ people. The contract is the team's source of truth.

### Lockfile rule
If two people change `pubspec.yaml`, the second to merge regenerates
`pubspec.lock`. Don't commit conflict markers.

### Daily standup
3-line written standup in the team chat at start of day:
- Yesterday: …
- Today: …
- Blocked: … (or "no")

### Weekly sync
30 min on Sunday. Review what's shipped, what's blocked, recalibrate the demo
schedule.

### When in doubt
Check [api-contract.md](./api-contract.md). If it doesn't answer, ask in chat.
If still unclear, **don't guess** — pause and clarify. A 5-minute conversation
saves 5 hours of rework.

---

## 6. Demo day prep (last week of May / first week of June)

| Day | What happens |
|---|---|
| -7 days | Feature freeze. Bug bash only. |
| -5 days | Demo script locked. Each track owner records a 30-second walkthrough of their slice. |
| -3 days | Dry run with TA. Note every confusing moment. |
| -2 days | Build APK + iOS testflight from `main`. Distribute to team. |
| -1 day | Each person uses the app for an hour. Last bug fixes. |
| **Demo day** | One person drives, others handle Q&A. Build cut at start of day, no changes after. |

### Demo script (already in [product-brief.md](./product-brief.md))

> "Most career tools are a dashboard of features. We built an agent.
>
> Watch — I type one sentence: *'help me apply to a UX role at an AI startup.'*
> The agent reads my resume, searches live job boards, picks the best fit,
> rewrites my resume to match, and drafts an email to the hiring manager. I
> press send. Done."

---

## 7. Quick reference — who answers what

| If you have a question about… | Ask… |
|---|---|
| Anything resume / PDF / template | Track B1 |
| JSearch / Gmail / Hunter integrations | Track B2 |
| Agent loop, prompts, tool descriptions | Track B3 |
| Sign-in, navigation, settings, build config | Track FE1 |
| Chat UI, email review modal, decision cards | Track FE2 |
| What we agreed to build | [product-brief.md](./product-brief.md) + [api-contract.md](./api-contract.md) |
| What we agreed NOT to build | [api-contract.md §9](./api-contract.md) |
| How the existing code works | grep first, then ask in chat |

---

## 8. After demo

- `rm -rf backend/` — the Python directory.
- Rotate every API key.
- Write up what we'd ship in v2: chat persistence, cross-device sync, push
  notifications, scheduled brief generation, auto-submit (gated by autonomy
  level). All explicitly out of scope for v1.

Go ship something good.
