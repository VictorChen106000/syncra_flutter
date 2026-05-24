# Syncra — Status & Plan

**Demo day:** June 16, 2026 · **Today:** 2026-05-21 · **~26 days out.**

The live tracker of what's done, what's left, and who owns it. Update this as
work lands. Product context: [README.md](./README.md). Technical contract:
[ARCHITECTURE.md](./ARCHITECTURE.md).

## Workstreams

Five workstreams, one owner each (5-person team). Plain names — no codes.

| Workstream | Scope |
|---|---|
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
- Tool registry + 10 tools registered (mix of real and stub — see below)
- Resume upload (Storage blob + Firestore metadata) · PDF text extraction · lazy resume parser → `ResumeJSON`
- Fixed PDF template · resume tailor orchestrator
- `tailor_resume` proposes edits and the loop pauses · read-only `ProposedEditsBlock` preview in chat
- `read_resume`, `match_jobs`, `save_to_pipeline`, `save_to_tracker`, `remember_fact` — real implementations
- Applications activity-log (drafted / sent / "got reply") · pipeline approve → application
- Dashboard prompt entry + "Run today's brief" CTA · Settings (autonomy, brief toggle, delete account) · onboarding role capture · router redirects
- Live notifications inbox subscribed to agent events

## 🔲 Remaining work

### Resume Engine
The propose path and accepted-edit preview/save path work. Remaining engine polish:

- [x] **`resume_diff_service.dart`** — pure accepted-edit application with target-path / verbatim-original backstop.
- [x] Accepted edits can render a tailored PDF preview and save it as a tailored resume.
- [ ] Cascade-delete tailored children when a manual resume is deleted (`ResumeNotifier.deleteResume`).
- [ ] Parser retry — one stricter-prompt retry on malformed JSON for `read_resume` / tailor edits.
- [ ] Scanned-PDF: when text extraction returns empty, surface "upload a text PDF" instead of falling back to the sample resume.

### Resume Diff UI
The inline proposed-edits card is now interactive.

- [x] `ProposedEditsBlock` supports per-edit Accept/Reject decisions, accepted counter, Dismiss all, and Apply N edits.
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

- [ ] **Wire the modal in** — `EmailReviewPage.show` has no caller. A `draft_email` chat result needs a "Review & send" button that opens it. This is a chat-block change (Agent Reasoning / Resume Diff UI), not a service — the modal's own header comment flags it as a deliberate handoff. Until it lands, the Gmail send path is built but unreachable.

### Agent Reasoning
Loop, prompts, and tools are in place. Current status:

- [x] `ask_user` pauses and resumes the same running tool loop.
- [x] After a tailored resume is saved, `tailored_resume_id` is fed back into the threaded conversation so the agent can continue the workflow.
- [x] `ActionProposalBlock` approvals now carry a hidden continuation prompt and resume the agent loop after the user taps Accept.
- [x] Main agent prompt is regression-tested for goal-oriented workflow behavior, approval gates, saved-resume continuation, and `send_email` safety.
- [x] `tailor_resume` prompt is regression-tested: no full-section rewrites, every `original_text` must be verbatim, and no invented experience.

Remaining / delegated:

- [ ] Email draft review handoff: wire `draft_email` results to a chat block/button that opens `EmailReviewPage.show`.
- [ ] `draft_email` should use real selected/uploaded resume context instead of sample resume fallback.

### App Shell
Effectively complete. Empty states (resume / pipeline / applications) already
ship with one-tap CTAs; morning brief is now opt-in. Remaining:

- [ ] Add the `gmail.send` OAuth scope — **blocked on Integrations**; do it when the Gmail work lands.
- [ ] Optional polish pass — animations, snackbar / error consistency.

Done 2026-05-21 — **morning brief is opt-in.** The router routes to the morning
brief page after sign-in only when `morning_brief_enabled` is true (off by
default); otherwise sign-in lands on the dashboard. The Profile → "Today's
brief" toggle controls it and no longer fires the brief (no token spend) when
flipped — the brief runs only from the dashboard CTA or the post-sign-in page.

## 🐞 Known bugs / cleanup

- **`draft_email` uses the sample resume.** It hardcodes `kFakeResumeJson` and has no `resume_id` input — unlike `match_jobs` / `tailor_resume`. Wire it to `_loadResumeContextForAgent`. (ARCHITECTURE.md §3 is the target.)
- **Upload progress is fake** — `ResumeNotifier._uploadFile` sets `progress: 50` then jumps to 100. Cosmetic; wire real progress or simplify the UI.
- **Email/password sign-in is a stub** — `AuthNotifier.signInWithEmail` falls through to a guest session. Decide: wire Firebase email/password, or remove the login/signup form (the stack is Google-only).
- Delete `backend/` (the old Python directory) after the demo.

## Critical path

The headline demo moment — propose → review → apply → tailored PDF — is blocked
end to end:

```
Resume Engine: resume_diff_service + apply_resume_edits  ──┐
                                                          ├──► Resume Diff UI: interactive block + ResumeState V1/V2 ──► full tailor flow demoable
Agent Reasoning: feed apply result back into the loop   ──┘
```

Build **Resume Engine first** — it has no UI dependency and unblocks both the
diff UI and the agent loop. Integrations (JSearch, Gmail) is independent and can
run in parallel.

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
