# Syncra — Status & Plan

**Demo day:** June 16, 2026 · **Today:** 2026-06-05 · **~11 days out.**

The live tracker of what's done, what's left, and who owns it. Update this as
work lands. Product context: [README.md](./README.md). Technical contract:
[ARCHITECTURE.md](./ARCHITECTURE.md).

## Workstreams

Five workstreams, one owner each (5-person team). Plain names — no codes.

| Workstream | Scope |
| --- | --- |
| **Resume Engine** | Resume models, parsing, diff engine, PDF render, `tailor_resume` + `apply_resume_edits` tools |
| **Resume Diff UI** | The inline accept/reject diff block, resume list/preview, `ResumeState` V1/V2 |
| **Agent Reasoning** | Claude tool-use loop, prompts, tool descriptions, brief reasoner |
| **App Shell** | Riverpod, navigation, auth/onboarding, dashboard, settings, applications, notifications |
| **Integrations** | JSearch, Gmail send, email review modal |

## ✅ Shipped — don't rebuild

Foundation, verified in code:

- Google Sign-In · Firestore + owner-only rules · Firebase Storage for resume blobs
- Riverpod migration — all controllers are immutable `Notifier`s
- Agent chat with the full tool-use loop · `ask_user` mid-flow input · extended thinking
- Tool registry with real job-search, resume, memory, Trust Guard, pipeline, tracker, and email tools
- Resume upload (Storage blob + Firestore metadata) · PDF text extraction · lazy resume parser → `ResumeJSON`
- Fixed PDF template · resume tailor orchestrator
- `tailor_resume` proposes edits and the loop pauses · read-only `ProposedEditsBlock` preview in chat
- `read_resume`, `match_jobs`, `check_job_risk`, `save_to_pipeline`, `save_to_tracker`, `remember_fact` — real implementations
- Trust Guard checks obvious job red flags, persists results on pipeline/application records, surfaces badges/details in UI, and has unit tests
- Applications activity-log (drafted / sent / "got reply") · pipeline approve → application
- Dashboard prompt entry + "Run today's brief" CTA · Settings (autonomy, brief toggle, delete account) · onboarding role capture · router redirects
- Live notifications inbox subscribed to agent events

## 🔲 Remaining work

### Resume Engine

The propose path and accepted-edit preview/save path work. Remaining engine polish:

- [x] **`resume_diff_service.dart`** — pure accepted-edit application with target-path / verbatim-original backstop.
- [x] Accepted edits can render a tailored PDF preview and save it as a tailored resume.
- [x] Cascade-delete tailored children when a manual resume is deleted (`ResumeNotifier.deleteResume`).
- [x] Parser retry — `ResumeParserService` retries once with a stricter prompt when Claude returns malformed resume JSON, then surfaces an actionable parse error if retry still fails.
- [x] Scanned-PDF / empty text guard: parser and tailor flow surface an actionable text-PDF error instead of falling back to a sample resume.

### Resume Diff UI

The inline proposed-edits card is now interactive.

- [x] `ProposedEditsBlock` renders the current read-only proposed-edits card state with accepted counter, Dismiss all, Apply N edits, preview-ready state, and current widget tests.
- [x] Applying accepted edits renders an in-memory tailored PDF preview.
- [x] Saving the preview persists the tailored resume to Firebase Storage / Firestore and returns a saved resume id.
- [x] After save, the agent loop resumes through the saved-resume continuation bridge.

Remaining / delegated:

- [ ] Polish final diff-session state ownership if the team still wants the decisions mirrored in `ResumeState`.
- [ ] Confirm final preview / save UX with Resume Diff UI owner.

### Integrations

Service layer complete — JSearch, Gmail, and the email review modal all ship.
One cross-workstream wire remains (see below).

- [x] `jsearch_service.dart` — live RapidAPI search, `jobs/` upsert, 1h cache; `search_jobs` uses it (falls back to the seeded catalogue with no key).
- [x] `gmail_service.dart` + `lib/features/email/` — raw `users.messages.send`, OAuth via `google_sign_in` v7; `gmail.send` scope hinted at sign-in.
- [x] `email_send_service.dart` — one-shot confirmation-token gate; the real `send_email` handler refuses tokenless (autonomous) calls.
- [x] `email_review_page.dart` — editable review sheet that mints the token and sends.
- [x] `lookup_hiring_manager` — returns the company's `careers@` address; no named-contact lookup (Hunter.io considered and dropped 2026-05-21).

- [x] Email review UI is reachable from chat email draft blocks and the manual job action sheet.

### Agent Reasoning

Loop, prompts, and tools are in place. Current status:

- [x] `ask_user` pauses and resumes the same running tool loop.
- [x] After a tailored resume is saved, `tailored_resume_id` is fed back into the threaded conversation so the agent can continue the workflow.
- [x] `ActionProposalBlock` approvals now carry a hidden continuation prompt and resume the agent loop after the user taps Accept.
- [x] Main agent prompt is regression-tested for goal-oriented workflow behavior, approval gates, saved-resume continuation, and `send_email` safety.
- [x] `tailor_resume` prompt is regression-tested: no full-section rewrites, every `original_text` must be verbatim, and no invented experience.
- [x] Morning brief Trust Guard prompt is regression-tested: `check_job_risk` runs before `save_to_pipeline`, medium/high-risk jobs are skipped, no outreach is attempted, no user questions are asked, and the no-resume fallback still runs Trust Guard.
- [x] `draft_email` uses real selected/uploaded resume context through `_loadResumeContextForAgent`, defaults to the latest manual resume, and attaches the chosen or tailored PDF.

Remaining / delegated:

- [x] Email draft review handoff: `draft_email` results render a reviewable email draft block that opens `EmailReviewPage.show`.

### App Shell

Effectively complete. Empty states (resume / pipeline / applications) already
ship with one-tap CTAs; morning brief is now opt-in. Remaining:

- [x] Gmail compose/send OAuth scopes are requested by the Gmail link flow.
- [x] Email/password auth uses Firebase email/password sign-in and account creation; it no longer falls through to guest mode.
- [x] Resume upload progress is wired to Firebase Storage transfer progress.
- [ ] Optional polish pass — animations, snackbar / error consistency.

Done 2026-06-05 — **morning brief is controlled by the current router/dev-flag
flow.** Returning signed-in users can be routed to the morning brief once per app
session, devs can force-preview it with the debug flag, and the actual brief
still runs only through the agent tool loop.

## 🐞 Known bugs / cleanup

- Delete `backend/` (the old Python directory) after the demo.

## Critical path

The headline demo moment — propose → review → apply → tailored PDF — is now
demoable end to end:

```text
Resume Engine: resume_diff_service + apply_resume_edits  ──┐
                                                         ├──► Resume Diff UI: read-only change log + tailored preview ──► full tailor flow demoable
Agent Reasoning: feed apply result back into the loop   ──┘
```

Resume Engine, Resume Diff UI, and Agent Reasoning are now integrated for the
core tailored-resume loop. Remaining work should focus on demo polish, bug bash,
and key configuration.

## Integration handshakes — agree these early

- **`ProposedEdit` + `ResumeDiffService` signatures** — Resume Engine ships them; Resume Diff UI imports them. Lock day one; UI builds against a fixture until then.
- **`apply_resume_edits` result → loop** — Resume Diff UI dispatches the tool; Agent Reasoning feeds the `tailored_resume_id` tool_result back into the conversation. Agree how the synthetic result re-enters the loop.
- **Email confirmation token** — the email modal generates a one-shot UUID; `send_email` validates it. Integrations owns both ends.
- **`gmail.send` OAuth scope** — App Shell adds it to Google Sign-In; Integrations consumes it.
- **Agent event stream** — already wired: `AgentChatNotifier` forwards every event to `NotificationsNotifier.onAgentEvent`.

## Demo-day checklist

- [ ] Feature freeze ~7 days out — bug bash only.
- [ ] `ANTHROPIC_API_KEY` + `RAPIDAPI_KEY` set; spend caps configured.
- [ ] Web: Firebase Storage CORS configured (skip if demoing on a device).
- [ ] Build APK / TestFlight from `main`; the whole team uses the app for an hour.
- [ ] Rotate every API key after the demo.
