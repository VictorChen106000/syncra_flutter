# Syncra — Team Plan

**Status:** v1.0 — work split for 5 people, demo June 16
**Audience:** the 5 of us
**Last updated:** 2026-05-16

Product context in [product-brief.md](./product-brief.md).
Architecture in [api-contract.md](./api-contract.md). When in doubt, contract wins.

---

## 0. Working agreements

| Rule | Why |
|---|---|
| **The contract is the source of truth.** | If you're about to invent a field or a method signature, check it first. |
| **No new external services without a team vote.** | Stack is already locked: Flutter + Firebase + Claude + JSearch + Gmail (+ Hunter optional). |
| **Branch per track.** Merge to `main` via PR. | Avoid stomp on shared files (mainly `app.dart`, `app_router.dart`). |
| **Lazy is fine. Stubs are fine.** Ship the shape, not perfection. | We have ~30 days. Polish in the last week. |
| **No backend server. Ever.** | Course rule. Anything that smells like "we need a server" — flag it on the group chat first. |
| **`debugPrint` is the production logger.** | No SDK, no telemetry. Keep it simple. |

---

## 1. The 5 tracks

Each track has an **owner** (replace placeholders with names),
a **goal** (the slice that ships),
files they primarily touch,
and **dependencies** on other tracks (so you know whose stuff is blocking you).

| Track | Owner | Slice |
|---|---|---|
| **A. Agent Core** | _TBD_ | The chat loop, tool registry, ask_user, decision cards |
| **B. Resume Pipeline** | _TBD_ | Local-cache upload, parse, tailor, fixed PDF template |
| **C. Jobs & Pipeline** | _TBD_ | JSearch integration, brief reasoner, pipeline cards, (stretch) Hunter |
| **D. Applications & Email** | _TBD_ | Tracker UI, application creation, Gmail send |
| **E. Auth, Shell & Polish** | _TBD_ | Firebase Auth, navigation, design system, onboarding, dashboard |

---

## 2. Track A — Agent Core

### Goal
Make the chat the primary UX. User types → agent picks tools → executes → emits result blocks → loops or pauses on `ask_user`.

### Owns
- [lib/features/agent_chat/](../lib/features/agent_chat/) (whole module)
- [lib/features/agent_chat/services/anthropic_chat_service.dart](../lib/features/agent_chat/services/anthropic_chat_service.dart) (extend to tool-use loop)
- `lib/features/agent_chat/tools/tool_registry.dart` (new)
- `lib/features/agent_chat/tools/tool_executor.dart` (new)
- [lib/features/agent_chat/models/agent_block.dart](../lib/features/agent_chat/models/agent_block.dart) (add `InputRequestBlock`)
- [lib/features/agent_chat/presentation/widgets/agent_block_views.dart](../lib/features/agent_chat/presentation/widgets/agent_block_views.dart)

### Build order
1. Extend `AnthropicChatService` to send `tools` array in the request and parse `tool_use` content blocks.
2. Build `ToolRegistry` with the schemas from contract §2 — start with `ask_user` only.
3. Add `InputRequestBlock` + chat UI for inline text field with submit.
4. Implement `ToolExecutor` that dispatches to registered tool handlers, returns `ToolResult` objects that get fed back to Claude as `tool_result` messages.
5. Wire tools from other tracks one by one as they ship (B → C → D).

### Dependencies
- **None to start.** Track A can stub all tools as `() => 'not implemented'` and demo the loop end-to-end with just `ask_user`.
- Later: depends on B's resume tools, C's job tools, D's application+email tools.

### Demo win
Show the chat asking a clarifying question mid-stream, user types into the inline field, agent continues. Even with stubbed downstream tools, this proves the loop works.

---

## 3. Track B — Resume Pipeline

### Goal
Upload → local file → (lazy) parse → tailor → render → save. Every resume goes through one fixed PDF template.

### Owns
- [lib/data/firestore/resumes_repository.dart](../lib/data/firestore/resumes_repository.dart) (swap from Firebase Storage to `path_provider`)
- [lib/features/resumes/](../lib/features/resumes/) (whole module)
- `lib/features/resumes/services/resume_parser_service.dart` (new)
- `lib/features/resumes/services/resume_tailor_service.dart` (new)
- `lib/features/resumes/services/pdf_template.dart` (new)
- Pubspec additions: `path_provider`, `pdf`, `syncfusion_flutter_pdf`

### Build order
1. **Local-cache swap.** Drop `firebase_storage` import. Write bytes to `${appDocs}/resumes/{id}.pdf` via `path_provider`. Save `local_path` to Firestore. Update preview page to read from local file.
2. **Parser service.** Given a `resume_id`, load PDF, extract text via `syncfusion_flutter_pdf`, call Claude with the resume-parser prompt, cache the resulting `resume_json` back into the Firestore doc.
3. **Tailor service.** Given `resume_id` + `job_id`, call parser if needed, call Claude with tailor prompt, return tailored `ResumeJSON`.
4. **PDF template.** Render `ResumeJSON` → bytes via `pdf` package, following the layout in contract §7.
5. **Glue.** Tool handlers for `read_resume`, `tailor_resume` that Track A's executor calls.

### Dependencies
- Pubspec changes — coordinate with Track E (whoever's last to merge takes the lockfile pain).
- Track A consumes your tool handlers but you don't have to wait for Track A; build the services + a test page that calls them directly.

### Demo win
Open the resume preview, tap a "Tailor for Linear" button → see a new PDF in the preview list ~10 seconds later, with the right bullets emphasized.

---

## 4. Track C — Jobs & Pipeline

### Goal
Live job listings from JSearch, cached in Firestore. Brief reasoner picks top matches. Optional: Hunter.io for hiring-manager lookup.

### Owns
- [lib/data/firestore/jobs_repository.dart](../lib/data/firestore/jobs_repository.dart) (extend with JSearch direct call)
- [lib/data/firestore/pipeline_repository.dart](../lib/data/firestore/pipeline_repository.dart)
- [lib/features/agent/services/anthropic_service.dart](../lib/features/agent/services/anthropic_service.dart) (brief reasoner, already exists)
- [lib/features/agent/state/passive_agent_controller.dart](../lib/features/agent/state/passive_agent_controller.dart)
- `lib/data/services/jsearch_service.dart` (new)
- (stretch) `lib/data/services/hunter_service.dart` (new)

### Build order
1. **JSearch service** — port the logic from old `backend/app/jobs/sources.py` to Dart. Direct HTTP call. Normalize each result into the `Job` shape. Upsert into `jobs/` with deterministic IDs.
2. **In-memory cache** — 1-hour TTL keyed on `(query, location)` to stay under JSearch's free quota.
3. **Tool handler for `search_jobs`** — Track A will invoke this.
4. **Brief reasoner cleanup** — already works; just confirm it reads from your refreshed `jobs/` collection.
5. **(Stretch) Hunter integration** — single `lookup_hiring_manager(company)` call, cache results by company in Firestore.

### Dependencies
- Get a RapidAPI key + Hunter key out-of-band (free signup, no card).
- Coordinate `--dart-define` flags with Track E (they own how the app boots).

### Demo win
Type "find me UX roles" in chat. Watch Claude call `search_jobs`, see real, current Linear/Vercel/etc. listings populate live. (Will only work with internet — flag offline limitation.)

---

## 5. Track D — Applications & Email

### Goal
Approve a job → application appears in tracker. Agent can draft + send emails through the user's Gmail.

### Owns
- [lib/data/firestore/applications_repository.dart](../lib/data/firestore/applications_repository.dart) (already exists, extend)
- [lib/features/tracker/](../lib/features/tracker/) (whole module)
- `lib/features/email/services/gmail_service.dart` (new)
- `lib/features/email/services/email_draft_service.dart` (new — calls Anthropic)
- `lib/features/email/presentation/email_review_page.dart` (new — modal with subject/body/edit/send)

### Build order
1. **Tracker UI** — already wired; verify status update and add-note flows work end-to-end (need user testing).
2. **Email draft service** — Claude call with `(job, resume_json, tone)` → `{ subject, body }`.
3. **Gmail OAuth scope.** Update `google_sign_in` config to request `gmail.send`. Test on Android + iOS.
4. **Gmail send service** — package `googleapis` + `googleapis_auth`. Build a MIME message with the tailored resume as PDF attachment. Post to `users.messages.send`.
5. **Review modal UI** — subject + body editable, "Send to {recipient}" button. The ONLY place `send_email` actually fires.
6. **Tool handlers** for `draft_email`, `send_email`, `save_to_tracker`.

### Dependencies
- Wait for Track B's tailor service to produce a real PDF attachment.
- Wait for Track C's `search_jobs` if you want a real recipient — otherwise hard-code one for early testing.

### Demo win
Agent drafts a Linear email, user reviews, taps Send. A real email shows up in the user's Gmail Sent folder and a row appears in the tracker.

---

## 6. Track E — Auth, Shell & Polish

### Goal
Everything that isn't a feature: navigation, design system, onboarding, dashboard, the splash → login → brief → home flow. Plus build configuration.

### Owns
- [lib/main.dart](../lib/main.dart), [lib/app.dart](../lib/app.dart), [lib/core/](../lib/core/) (router, theme, constants)
- [lib/features/auth/](../lib/features/auth/), [lib/features/dashboard/](../lib/features/dashboard/), [lib/features/profile/](../lib/features/profile/)
- [lib/shared/](../lib/shared/) (design-system widgets)
- Build config: `pubspec.yaml`, `--dart-define` flags, `flutter run` recipes for the team
- Firestore + storage rules deploy ([firestore.rules](../firestore.rules))

### Build order
1. **Build-time config doc** — write a README section listing every `--dart-define` flag and where each key comes from.
2. **Onboarding tweak** — capture `autonomy_level` and `role` from the user, write to `users/{uid}`.
3. **Dashboard "what would you like the agent to do?"** — prominent prompt entry that deep-links into the chat with a pre-filled message.
4. **Settings page** — autonomy slider, sign out, link to delete account.
5. **Empty states everywhere** — first-time user with no resume, no jobs, no applications.
6. **Polish loop** — animations, snackbars, error handling consistency.

### Dependencies
- Pretty much everyone else depends on you for routing + the provider tree. Be responsive on PR reviews.
- You're the "no" person on PRs that add new external services or restructure the data model.

### Demo win
The whole demo flows without a stutter. No "uhh just ignore that error toast" moments.

---

## 7. Cross-track schedule

Rough phases, ~30 days to demo.

### Week 1 (May 17–23) — foundations
- A: chat loop with stubbed tools, `ask_user` working end-to-end
- B: local-cache resume upload, pubspec deps in
- C: JSearch service + tool handler, brief reasoner verified against fresh data
- D: tracker UI verified, application creation working
- E: build config doc, dashboard prompt entry, onboarding captures autonomy

### Week 2 (May 24–30) — agent capabilities
- A: wire B's `read_resume` + `tailor_resume` tools into the loop
- B: parser service + tailor service + fixed PDF template
- C: `search_jobs` tool wired into A's executor
- D: email draft service + Gmail OAuth tested
- E: settings page, empty states pass

### Week 3 (May 31–June 6) — full agent loop
- A: integrate D's `draft_email` + `send_email` (with review modal)
- B: edge cases — malformed PDFs, oversized files, tailor failures
- C: (stretch) Hunter.io lookup
- D: review modal polish, send button explicit confirmation
- E: cross-platform check (iOS / Android / web), bug bash

### Week 4 (June 7–13) — bug bash + demo rehearsal
- Everyone: own bugs in your own track, rehearse the demo script in product-brief.md
- E: cuts the demo build, distributes APKs to the team for last-minute testing

### Week 5 (June 14–16) — demo day prep
- Day 1: locked build, all keys rotated, spend caps set
- Day 2: dry run with TA
- **Day 3: demo**

---

## 8. Decision log

When the team votes on something, log it here so we don't re-litigate.

| Date | Decision | Reasoning |
|---|---|---|
| 2026-05-15 | Backend removed, full migration to Flutter + Firebase + Anthropic direct | Course rule — only Flutter + Firebase |
| 2026-05-16 | Local-cache for resume PDFs, no Firebase Storage | Avoids Blaze plan, fully free |
| 2026-05-16 | Agent-first UX with tool-use loop | Differentiator vs feature-dashboard apps |
| 2026-05-16 | JSearch + Gmail confirmed; Hunter is stretch | Free tiers viable for demo scale |

---

## 9. Who answers what

| If you have a question about… | Ask… |
|---|---|
| The agent loop, tool registry, chat UI | Track A |
| Anything resume / PDF | Track B |
| Job listings, JSearch quota, hiring-manager lookup | Track C |
| The tracker, Gmail OAuth, the send button | Track D |
| Sign-in, routing, build config, Firestore rules | Track E |
| What we agreed to build | This doc + the contract |
| What we agreed NOT to build | Contract §9 |
