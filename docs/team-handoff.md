# Syncra — Team Handoff Packet

**For:** the 5-person team (3 backend + 2 frontend)
**Demo day:** June 16, 2026 (~30 days out)
**Last updated:** 2026-05-17

> **Changes since 2026-05-16 — read before you start your track:**
> - **Resume tailoring is now a "PR diff," not a wholesale rewrite.** `tailor_resume` proposes a list of targeted edits; the user accepts/rejects each one like a GitHub pull request. Only after the user applies does a tailored PDF get rendered. Touches B1, B3, FE1, FE2.
> - **Morning brief no longer auto-fires every 24h.** That design was burning Claude tokens on every app open. The brief is now opt-in (off by default) and user-triggered via a dashboard CTA. Touches B3 + FE1.
> - **FE1 migrates `provider` → `flutter_riverpod`** with strict immutable state. Required to make the diff viewer's accept/reject UX work without race conditions.

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
│   ├── roles/                        ✅ — per-person briefs (01-05), parallel to this doc
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

### Track 1 — Backend: Resume Diff Pipeline (B1)

**You own**
- [lib/features/resumes/](../lib/features/resumes/) — every service, model, repository
- [lib/data/firestore/resumes_repository.dart](../lib/data/firestore/resumes_repository.dart)
- The `read_resume`, **rewritten `tailor_resume`**, and **new `apply_resume_edits`** tool implementations in [builtin_tools.dart](../lib/features/agent_chat/tools/builtin_tools.dart)

**Why it matters**
The headline demo moment is no longer "the agent rewrites your resume." It's
**"the agent proposes a set of targeted edits, and the user reviews each one
like a GitHub pull request."** Your code is the engine: `tailor_resume`
produces structured `ProposedEdit` records (target path, original text,
proposed text, reason) — and *nothing else*. Only after the user accepts a
subset (in FE2's diff viewer) does `apply_resume_edits` build a fresh
`ResumeJSON` and render the tailored PDF. **The original resume is never
mutated.**

**Build order**
1. **Add a `ProposedEdit` model** in `lib/features/resumes/models/proposed_edit.dart`:
   ```dart
   class ProposedEdit {
     final String targetPath;   // e.g. "experience[0].bullets[2]"
     final String originalText;
     final String proposedText;
     final String reason;       // one sentence — why this helps for this job
   }
   ```
   Path syntax must match what `read_resume` returns in `ResumeJSON` so paths
   round-trip cleanly. Pin the grammar with a unit test before B3 starts
   prompting against it.

2. **Rewrite [resume_tailor_service.dart](../lib/features/resumes/services/resume_tailor_service.dart)** — instead of generating a new `ResumeJSON`, prompt Claude to return a JSON array of
   `ProposedEdit` records. Hard rules enforced post-response:
   - Every `original_text` must match the current resume verbatim (drop edits that don't).
   - `proposed_text` may rephrase but never invent experience, dates, or metrics.
   - 3–8 edits per call max. Keep the change footprint small so reviews stay tractable.

3. **New service: `resume_diff_service.dart`** — pure function
   `applyEdits(ResumeJSON original, List<ProposedEdit> accepted) → ResumeJSON`.
   Walks each `targetPath`, swaps `originalText` → `proposedText`. Deterministic
   and stateless — **FE1's controller will call this synchronously on every
   accept/reject in the diff viewer**, so it must not touch I/O.

4. **Tool `tailor_resume`** now returns `{ proposed_edits: [...] }`. **No PDF,
   no Firestore write.** This tool's role is purely *propose*. (~150 LOC
   simplification vs. the v1.2 orchestrator.)

5. **New tool `apply_resume_edits`** — input `{ resume_id, accepted_edits[] }`.
   This is the tool that does the render: builds V2 `ResumeJSON` via
   `resume_diff_service`, runs through [pdf_template.dart](../lib/features/resumes/services/pdf_template.dart),
   saves local file + Firestore doc with `source='tailored'`, returns
   `{ tailored_resume_id }`. **Only this tool produces a new resume document.**

6. **Scanned-PDF edge case** — if `PdfTextExtractor` returns an empty string,
   surface a friendly "this PDF looks like a scan — please upload a text PDF"
   error to the chat instead of falling back to the sample resume.

7. **Parser retry** — if Claude returns malformed JSON for `parseResume` *or*
   `tailor_resume`'s edit array, retry once with a stricter prompt before giving up.

8. **Cascade-delete tailored resumes** — when the user deletes a manual resume,
   also delete its tailored children. Wire up in `ResumeController.deleteResume`.

9. **(Stretch)** "Edit history" UI showing original PDF + each
   apply_resume_edits result grouped together on the resume list page.

**You're done when**
- Upload a real resume → trigger tailoring → `tailor_resume` returns 3–8
  `ProposedEdit` records in chat within ~10s; every `original_text` exists
  verbatim in the resume.
- After the user accepts some edits and FE2 calls `apply_resume_edits`, a
  tailored PDF appears in the resume list within ~5s.
- That tailored PDF reflects **only** the accepted edits — rejected ones leave
  the original text intact.
- Deleting the parent resume cleans up tailored children.

**Dependencies**
- You depend on **B3** for the prompt that produces high-quality `ProposedEdit` arrays.
- **FE1 + FE2 depend on you** for the `ProposedEdit` model and `resume_diff_service` to power the diff viewer.

**Common pitfalls**
- Don't render any PDF inside `tailor_resume`. Render only inside `apply_resume_edits`.
- Don't mutate the original `ResumeJSON` anywhere — `resume_diff_service.applyEdits` must return a fresh object.
- `target_path` parsing is fiddly (bracket indices vs. dotted keys). Lock the grammar in a test.
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
- [lib/features/agent_chat/tools/builtin_tools.dart](../lib/features/agent_chat/tools/builtin_tools.dart) — system prompt + tool descriptions
- [lib/features/agent/services/anthropic_service.dart](../lib/features/agent/services/anthropic_service.dart) — brief reasoner / job matcher
- [lib/features/agent/state/passive_agent_controller.dart](../lib/features/agent/state/passive_agent_controller.dart) — **now a user-triggered callable, not a scheduler (see §8)**

**Why it matters**
Two big shifts since v1.2 that touch every prompt you own:

1. **Tailoring is now a diff, not a rewrite.** Your prompts must teach Claude
   to propose small, targeted edits — not rewrite whole sections. The whole
   accept/reject UX only works if the model emits surgical changes the user
   can reason about one at a time.
2. **The morning brief no longer auto-fires.** It was burning Claude tokens on
   every app open. The passive controller becomes a callable invoked by an
   explicit user tap from the dashboard (FE1 owns the button).

**Build order**
1. **Run 10 demo prompts end-to-end** with the current setup. Log every Claude
   turn. Identify failure patterns.

2. **Tighten the `tailor_resume` prompt** in [anthropic_tool_calls.dart](../lib/features/agent_chat/tools/anthropic_tool_calls.dart). The model must:
   - Return JSON only: `{ "proposed_edits": [ { target_path, original_text, proposed_text, reason } ] }`
   - Quote `original_text` **verbatim** from the resume — B1 validates by string match and drops mismatches.
   - Propose 3–8 edits max, prioritized by relevance to the JD.
   - Never invent experience, employers, dates, metrics.
   - Prefer rewriting individual bullets over full-section rewrites.
   - Keep each `reason` to one sentence: *"Aligns with the JD's emphasis on growth metrics."*

3. **Tune the system prompt** in `anthropic_chat_service.dart`. Add: *"When
   tailoring a resume, you propose changes — you never overwrite. The user
   reviews every edit before it lands."* Also: prefer tools over guessing,
   use `ask_user` when stuck.

4. **Tool descriptions** in [builtin_tools.dart](../lib/features/agent_chat/tools/builtin_tools.dart) — Claude reads these to pick:
   - `tailor_resume`: *"Proposes targeted edits to the resume. Does not modify the resume. The user reviews each edit in a diff viewer before applying."*
   - `apply_resume_edits`: *"Call only after the user has reviewed proposed edits. Input is the subset the user accepted in the diff viewer."*
   - Make every other tool description tight, behavioral, and clear about when **not** to use.

5. **Loop sequencing — critical.** After `tailor_resume` returns
   `proposed_edits`, Claude must **stop and wait** — do not auto-call
   `apply_resume_edits` or `draft_email`. The user reviews via FE2's diff
   viewer; FE2 calls `apply_resume_edits` directly with the accepted subset;
   the resulting `tailored_resume_id` is fed back into the conversation as a
   synthetic tool result. Only then does Claude proceed to `draft_email`.

6. **`ask_user` from the agent side** — provide 2–3 suggestion chips unless
   the question is genuinely open-ended. Bake into the tool description.

7. **Loop safety nets** — `_maxLoopIterations` stays at 8. Add better recovery
   messages when the loop terminates because of repeated tool failures, not
   just iteration cap.

8. **Refactor `PassiveAgentController.runBrief()`** — the morning-brief change:
   - **Remove the 24h auto-fire** on app open. Delete the timer / app-resume hook entirely.
   - Expose `runBrief()` as a pure callable that FE1's "Run today's brief" button invokes.
   - Internally, call `AnthropicChatService.runAgent` with a canned brief prompt — same code path as user-typed prompts. Locks in the "one agent, two triggers" model where both triggers are now explicit user taps.
   - Persist `last_brief_at` for the dashboard's "Last brief: 2h ago" label, but **never read it to decide whether to auto-fire**.

9. **Implement `save_to_pipeline` tool** — see [api-contract.md §2.6b](./api-contract.md). Lets `runBrief()` persist pipeline cards through the tool registry instead of bypassing it.

10. **Implement `remember_fact` tool** + `users/{uid}/learned_facts/`
    collection — see [api-contract.md §2.6a](./api-contract.md). When the user
    answers an `ask_user`, the agent persists the answer. Future tailoring
    reads `learned_facts` via `read_resume` (extend that tool to include them).
    Strong demo moment. ~3h.

11. **Brief reasoner quality** — tune `_systemPrompt` in `anthropic_service.dart`
    so categorizations are sharper (fewer "exploration" defaults).

12. **Event-stream subscription** for FE2's notifications inbox — expose the
    agent's event stream above the chat controller so both the chat UI and the
    notifications page can subscribe.

**You're done when**
- `tailor_resume` returns 3–8 `ProposedEdit` records, each with a verbatim `original_text`, on every test prompt. No full-section rewrites slip through.
- After `tailor_resume` fires, the agent waits — it does not auto-call `draft_email` until the user has resolved the diff viewer.
- Tapping FE1's "Run today's brief" button produces the same brief flow that auto-fired in v1.2, but **only on explicit tap** — nothing runs on app launch.
- Vague prompts trigger `ask_user` with suggestion chips, not random tool fires.
- Specific prompts produce search → read_resume → match → tailor (propose edits) → wait → apply → draft chain.

**Dependencies**
- **B1** owns the `ProposedEdit` model + `apply_resume_edits` executor. Agree on the schema in week 1.
- **FE2** owns the diff viewer + the trigger that calls `apply_resume_edits`. Agree on how the resulting tool_result is fed back into the agent loop.
- **FE1** owns the dashboard "Run today's brief" button + the morning-brief settings toggle.

**Common pitfalls**
- Don't let Claude call `apply_resume_edits` itself. That tool is user-triggered via UI only.
- Don't let the `tailor_resume` prompt drift back to full-section rewrites. Test for it weekly with a regression prompt set.
- Don't re-introduce the 24h auto-fire as a "small convenience." It's a token-cost regression.
- Don't add new tools without updating [api-contract.md §2](./api-contract.md).
- Don't increase `_maxLoopIterations` past 10 without thinking about cost.

---

### Track 4 — Frontend: Shell, State, Onboarding, Applications (FE1)

**You own**
- [lib/core/router/](../lib/core/router/) — navigation
- [lib/app.dart](../lib/app.dart) — **state container, now a Riverpod `ProviderScope`** (touch carefully — coordinate with B3 on the chat/passive controllers)
- [lib/features/auth/](../lib/features/auth/) — sign-in, splash, onboarding
- [lib/features/dashboard/](../lib/features/dashboard/) — landing screen + **"Run today's brief" CTA**
- [lib/features/profile/](../lib/features/profile/) — settings page (autonomy slider, morning-brief toggle, sign out)
- [lib/features/applications/presentation/](../lib/features/applications/presentation/) — Applications UI
- [lib/shared/widgets/](../lib/shared/widgets/) — design system
- Build configuration — `--dart-define` recipes, README setup section
- Firebase project config — when Track 2 adds Gmail scope, you coordinate

**Why it matters**
Two structural shifts since v1.2 sit on your desk:

1. **Migrate `provider` → `flutter_riverpod` with strict immutable state.**
   Required to make the diff-viewer's accept/reject UX work cleanly: the
   `ResumeController` must hold the original `ResumeJSON` (V1) and a
   separately-derived proposed `ResumeJSON` (V2) at the same time, and FE2
   needs to render either one without race conditions. The legacy `provider`
   pattern of mutating a single controller in place won't survive this.
2. **Kill the 24h auto-brief.** It was burning Claude tokens on every app
   open. Replace with an opt-in setting + an explicit dashboard CTA.

Beyond that: the shell is what makes the app feel like a *product*. Empty
states, smooth navigation, an onboarding that captures real data — that's all you.

**Build order**

1. **Migrate `provider` → `flutter_riverpod` in one PR.** Add `flutter_riverpod`
   to pubspec, remove `provider`. Convert each controller (`AuthController`,
   `ResumeController`, `ApplicationsController`, `JobsController`,
   `NotificationsController`, `AgentChatController`, `PassiveAgentController`)
   to a Riverpod `Notifier<T>` with an **immutable** state class. Replace
   `Consumer<X>` / `context.read<X>()` with `ref.watch(xProvider)` /
   `ref.read(xProvider.notifier)`. Coordinate the merge with B3 — they touch
   the chat controller heavily.

2. **`ResumeController` state shape — the load-bearing change for the diff viewer:**
   ```dart
   class ResumeState {
     final ResumeJSON? original;          // V1 — never mutated
     final ResumeJSON? proposed;          // V2 — original with accepted edits applied
     final List<ProposedEdit> pending;    // not yet accepted or rejected
     final Set<String> acceptedPaths;     // target_paths the user has accepted
   }
   ```
   - `acceptEdit(edit)` → add to `acceptedPaths`, recompute `proposed` by calling B1's `resume_diff_service.applyEdits(original, acceptedSubset)`. Emit a new `ResumeState` (no in-place mutation).
   - `rejectEdit(edit)` → remove from `pending`, leave `proposed` unchanged.
   - `clearProposal()` → reset `pending`, `acceptedPaths`, `proposed` (called when user navigates away or starts a new tailor).
   - The controller **never overwrites `original`**. Even after `apply_resume_edits` renders the tailored PDF, that's a *new* Firestore resume doc with `source='tailored'`; the original stays put.

3. **Onboarding capture — actually persist this time.** Capture `role`
   (free-text e.g. "Senior UX Designer") and write to `users/{uid}` via a new
   `UserRepository.update()` method. The brief reasoner already reads `role`.
   **Do not capture `autonomy_level` in onboarding** — defer to Settings. The
   user has no context to choose it yet, and getting it wrong here is worse
   than leaving it at the default.

4. **Dashboard "Run today's brief" CTA** — a prominent button or card that
   calls `ref.read(passiveAgentProvider.notifier).runBrief()`. Show last-run
   timestamp ("Last brief: 2 hours ago") so the user knows whether to tap
   again. **Do not auto-fire on app open.** This is the v1.2 → v1.3 fix that
   protects token spend.

5. **Dashboard prompt entry** — a prominent input that, on send, dispatches the
   prompt to the chat controller AND navigates to chat. Today the dashboard
   "send" button just teleports without sending the text — fix this when you
   touch it.

6. **Settings page** — replace [lib/features/profile/presentation/profile_page.dart](../lib/features/profile/presentation/profile_page.dart) with a real one:
   - **Autonomy slider** — `suggest` / `ask_first` / `auto_apply`, default `ask_first`.
   - **Morning brief toggle** — off by default. When on, dashboard shows a stronger "Today's brief is ready" prompt; still requires a tap to fire.
   - Sign out, delete account.
   - Persist all settings to `users/{uid}` via `UserRepository.update()`.

7. **Activity-log refactor of the Applications page** — drop the multi-stage
   status enum (viewed/replied/interview/offer/rejected) per
   [api-contract.md §3](./api-contract.md). New fields: `drafted_at`,
   `sent_at`, `got_reply` (user-flippable bool), `follow_up_at`, `notes`.
   Rebuild [applications_page.dart](../lib/features/applications/presentation/applications_page.dart)
   as a date-sorted activity log with a "Got a reply" switch per entry. Filter
   chips become `All / Drafts / Sent / Replied`. Coordinate with
   [ApplicationsController](../lib/features/applications/state/applications_controller.dart) and
   [ApplicationsRepository](../lib/data/firestore/applications_repository.dart). ~4–5h.

8. **Empty states everywhere** — first-time user with no resume, no jobs in
   pipeline, no applications. Each empty state explains how to start AND
   offers a one-tap action.

9. **Build config doc** — a README section listing every `--dart-define` flag,
   where each key comes from, and a single `flutter run` command that has them
   all.

10. **Polish loop** — animations, snackbar consistency, error styling.

**You're done when**
- All controllers are Riverpod `Notifier`s returning immutable state; the `provider` package is removed from pubspec.
- `ResumeController` holds V1 and V2 simultaneously; FE2's diff viewer can render either without flicker.
- A brand-new user: signs in → captures role → lands on dashboard → sees "Run today's brief" CTA that does nothing until tapped → onboarding does not silently spend Claude tokens.
- Settings page exists; morning-brief toggle and autonomy slider both work and persist.
- Applications page renders as a date-sorted activity log.
- README has a working "how to run this app" section.

**Dependencies**
- Coordinate with **B3** on the Riverpod migration of `AgentChatController` and `PassiveAgentController`.
- Coordinate with **B1** on the `ResumeState` shape — they import `ProposedEdit` and `resume_diff_service`.
- Coordinate with **B2** on the Gmail OAuth scope addition to Google Sign-In.
- Coordinate with **FE2** on consistent navigation patterns.

**Common pitfalls**
- Don't half-migrate. A codebase with both `provider` and `flutter_riverpod` is a debugging nightmare. Land the migration in one PR.
- Don't expose mutable lists/maps in state classes — use `List.unmodifiable` or freeze-style copy semantics. Mutation in state breaks Riverpod's diffing.
- Don't compute V2 in widgets. The controller is the only place that calls `applyEdits`.
- Don't bring back the 24h auto-brief as a "convenience" — it's a token-cost regression.
- Don't break the `go_router` redirect logic — it handles auth-gating.
- Don't add a new top-level dependency without team vote.

---

### Track 5 — Frontend: Inline Diff Block, Email Modal, Notifications (FE2)

**You own**
- [lib/features/agent_chat/presentation/](../lib/features/agent_chat/presentation/) — chat UI polish
- `lib/features/agent_chat/presentation/widgets/proposed_edits_block.dart` — **create this — the headline UI of v1.3, inline in the chat**
- [lib/features/resumes/presentation/](../lib/features/resumes/presentation/) — resume list / preview (output viewers; not the review surface)
- [lib/features/notifications/](../lib/features/notifications/) — **upgrade from static list to live agent-event inbox**
- `lib/features/email/presentation/email_review_page.dart` — **create this**

**Why it matters**
You build the surface where the agent's proposed edits meet the user's
judgment. The whole "user stays in control" promise from the brief lives or
dies here. Three pieces of UI gate the critical actions:

- The **inline `ProposedEditsBlock`** — the headline UI of the v1.3 pivot.
  Renders **inside the chat stream** (not on a separate page). The user
  reviews each edit as a discrete Accept/Reject like a GitHub PR, then taps
  "Apply N edits" in the block's footer. No navigation hop — the user lives
  in the chat and the review happens there too.
- The **email review modal** — without it, B2 can't ship `send_email` safely.
- The **notifications inbox** — without it, the user is trapped inside chat
  while the agent works.

**Build order**

1. **`InputRequestView` polish** — text field expansion smooth, suggestion chips beautiful, "answered" state distinct.

2. **`ProposedEditsBlock` — the headline build, inline in chat.** Create
   `lib/features/agent_chat/presentation/widgets/proposed_edits_block.dart`
   (your file — no collision with A's other block renderers). When the
   `tailor_resume` tool result lands in the chat stream, this block renders
   inline between the agent's text message and whatever comes next.

   A adds a single `case ProposedEditsBlock` in `agent_block_views.dart` that
   delegates to your widget. You own the widget; A wires the case.

   ```
   [agent: "I've reviewed your resume against the Linear JD. Here are 5 edits."]

   ┌─ 5 proposed edits · 0/5 accepted ──────────────┐
   │                                  [×]  [✓ all]  │
   ├────────────────────────────────────────────────┤
   │  EXPERIENCE › ACME CORP › BULLET 3             │
   │  − Shipped feature X to 200K users.            │  ← original, strikethrough
   │  + Led the launch of feature X to 200K users,  │  ← proposed
   │    lifting D7 retention 18%.                   │
   │  💡 Aligns with the JD's growth metrics.      │
   │  [ Reject ]                  [ Accept ]        │
   ├────────────────────────────────────────────────┤
   │  ... 4 more edits ...                          │
   ├────────────────────────────────────────────────┤
   │      [ Apply N edits → render tailored PDF ]   │  ← sticky footer-in-block
   └────────────────────────────────────────────────┘

   [agent waits — no follow-up blocks until user resolves]
   ```

   - **Per-card Accept** → `ref.read(resumeProvider.notifier).acceptEdit(edit)`. The controller adds to `acceptedPaths` and recomputes V2 via B1's `resume_diff_service.applyEdits`. Header counter updates instantly.
   - **Per-card Reject** → `rejectEdit(edit)`. Card collapses with a "rejected" badge; V2 reverts that path. **No PDF render.**
   - **Header** — `"{accepted}/{total} accepted"` + bulk Accept all / Reject all.
   - **Footer CTA** — "Apply N edits" only enabled when `acceptedPaths.isNotEmpty`. Tapping calls A's chat controller method to dispatch `apply_resume_edits`. The agent loop resumes; a new tool result block appears below: *"Tailored for {Job} — [View PDF]"*.
   - **Empty-after-resolve** — if user resolved all edits with zero accepted, footer shows *"No changes accepted — original resume kept"*. Do **not** call `apply_resume_edits`.
   - **Long lists** — each card collapsible when there are >5 edits (collapsed = section path; expanded = full diff). Keep the chat scrollable.

3. **Tailored-result link** — when the apply tool result lands, the result
   block links to `resume_preview_page.dart` so the user can see the
   rendered tailored PDF. (Quick wire, ~30 min.) The old v1.2 "Tailored
   {file} — Preview / Save / Discard" decision card is dead under the diff
   model; delete it.

4. **Live preview pane (stretch, tablet/web).** Right-side pane that renders
   the ResumeJSON V2 live as the user accepts/rejects in the `ProposedEditsBlock`.
   **Debounce** at ~400ms; don't render on every tap. On mobile, skip — the
   block IS the review surface.

5. **Notifications inbox upgrade** — rewrite the existing static list as a
   live subscription on B3's agent event stream. Each `ask_user` and tool
   completion that fires while the user isn't on the chat page becomes an
   inbox entry. Tapping shows the inline surface:
   - For `ask_user` events → inline text field + suggestion chips.
   - For `tailor_resume` results → **deep-link back into chat scrolled to the `ProposedEditsBlock`**. Don't try to render the diff inside the notification card or build a separate review surface.
   - For other tool completions → the appropriate decision surface.
   Coordinate with B3 on the `AgentEvent` stream shape.

6. **Email review modal** — modal sheet with editable subject + body, "Send to
   {recipient}" button. Tap → `confirmAndSendEmail(token)` → triggers B2's
   `send_email` tool with a one-shot UUID confirmation token. Coordinate with B2 on the token shape.

7. **Resume preview improvements** — when the local file is missing (different device), show a clear "this resume isn't on this device" state with a re-upload button.

8. **`tailor_page.dart`** — drop or repurpose as a simple entry point that pre-fills a chat prompt ("Tailor my resume for {Job Title}"). The review itself now happens in the inline `ProposedEditsBlock`, not on a separate page.

9. **Cross-platform check** — iOS, Android, web. File issues against FE1 for shell-layer bugs.

**You're done when**
- After `tailor_resume` fires, the chat scrolls to a `ProposedEditsBlock` inline — no navigation hop.
- In the block, every edit has its own Accept/Reject pair. Accepting one edit instantly updates the header counter (and, if preview is on, the rendered resume).
- Rejecting an edit removes it from the list and reverts that field to original **instantly — no PDF render needed**.
- The "Apply N edits" CTA only enables when `acceptedPaths.isNotEmpty`; tapping renders the tailored PDF and resumes the agent loop with the new `tailored_resume_id`.
- The user can close chat mid-loop → see a notification → tap → answer (text field) or return to chat scrolled to the `ProposedEditsBlock`.
- Email review modal exists, is editable, and the send button is the **only** path to actually sending an email.
- App looks correct on iOS and Android.

**Dependencies**
- **B1** owns the `ProposedEdit` model and `resume_diff_service.applyEdits()` — you import both.
- **B3** controls the chat block emitted when `tailor_resume` returns + the event stream for notifications.
- **B2** controls when `send_email` fires — agree on the confirmation-token handshake (one-shot UUID generated by the modal, passed to the tool, validated on the receiving side).
- **FE1** owns the Riverpod migration — your UI binds to `ref.watch(resumeProvider)`, not `Consumer<ResumeController>`.

**Common pitfalls**
- Don't compute V2 in the UI layer. Always call `resumeProvider.notifier.acceptEdit()` so state stays single-source-of-truth.
- Don't render the tailored PDF preview on every accept tap — debounce, or render only on explicit Preview action.
- Don't let "Apply N edits" be tappable while `acceptedPaths` is empty.
- Don't try to render the diff *inside* a notification card — deep-link back into chat at the `ProposedEditsBlock`.
- Don't bypass the email review modal for `send_email` — the whole point of that modal is "the user explicitly tapped Send."
- Don't add markdown rendering to text blocks unless B3 says the agent will emit markdown. Right now it doesn't.
- Don't fork the design-system widgets — extend the ones in [lib/shared/widgets/](../lib/shared/widgets/).

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
