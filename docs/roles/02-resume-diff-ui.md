# Role 2 — Resume Diff UI (R2, Frontend)

**Track:** R2 — Resume Diff UI
**Estimated hours:** ~10–12h
**Demo day:** 2026-06-16
**Companion role:** R1 (Resume Engine) — you import their model + service

---

## The 30-second context

Syncra is a Flutter + Firebase career-agent app. The headline demo moment is:
the agent proposes a list of targeted resume edits, the user reviews each one
like a GitHub pull request, and the accepted subset becomes a tailored PDF.

**You own the user-facing surface.** R1 produces the data (proposed edits
+ the pure function that applies them); you render the diff page, manage the
controller state, and let the user accept/reject each edit. The whole
"user stays in control" promise from the product brief lives in your UI.

Stack: Flutter, Riverpod (replacing `provider`), strict immutable state.

---

## What's already shipped in YOUR area

| Piece | Status |
|---|---|
| `resume_lists_page.dart` — list of resumes | ✅ |
| `resume_preview_page.dart` — local PDF viewer | ✅ |
| `ResumeController` (Provider-based, wholesale shape) | ⚠️ — rewrite as Riverpod Notifier with diff state |
| `resume_diff_page.dart` | ❌ — create (the headline build) |
| Decision card in `agent_block_views.dart` | ❌ — create (compact "{N} edits — Review" card) |
| `tailor_page.dart` | 🟡 — wire to diff flow |

---

## What you need to build

### 1. ResumeController as Riverpod Notifier (~3h)
After F (App Shell) publishes the Riverpod pattern (day 1), convert
[lib/features/resumes/state/resume_controller.dart](../../lib/features/resumes/state/resume_controller.dart)
to a `Notifier<ResumeState>` with this state shape:

```dart
class ResumeState {
  final ResumeJSON? original;          // V1 — never mutated
  final ResumeJSON? proposed;          // V2 — original with accepted edits applied
  final List<ProposedEdit> pending;    // not yet accepted or rejected
  final Set<String> acceptedPaths;     // target_paths the user has accepted
  // + the existing fields for resume list, selected resumes, etc.
}
```

Methods (all emit a new immutable `ResumeState`):
- `setProposal(List<ProposedEdit> edits)` — called when `tailor_resume` tool result lands. Sets `pending = edits`, `acceptedPaths = {}`, `proposed = original`.
- `acceptEdit(ProposedEdit edit)` — adds edit's path to `acceptedPaths`, recomputes `proposed` by calling `ResumeDiffService.applyEdits(original, acceptedSubset)`.
- `rejectEdit(ProposedEdit edit)` — removes from `pending`, leaves `proposed` unchanged.
- `clearProposal()` — when user navigates away / starts new tailor.

**Critical:** never overwrite `original`. Even after `apply_resume_edits`
renders the tailored PDF, that's a *new* Firestore resume doc — `original`
stays put.

### 2. Resume Diff Page (~5h) — THE HEADLINE BUILD
Create [lib/features/resumes/presentation/resume_diff_page.dart](../../lib/features/resumes/presentation/resume_diff_page.dart).

Layout — each ProposedEdit is its own card:

```
┌──────────────────────────────────────────────┐
│ EXPERIENCE › ACME CORP › BULLET 3            │
│                                              │
│  − Shipped feature X to 200K users.          │  ← original, red strikethrough
│  + Led the launch of feature X to 200K       │  ← proposed, green
│    users, lifting D7 retention 18%.          │
│                                              │
│  💡 Aligns with the JD's emphasis on        │  ← reason
│     growth metrics.                          │
│                                              │
│  [ Reject ]              [ Accept ]          │
└──────────────────────────────────────────────┘
```

Wiring:
- **Accept** → `ref.read(resumeProvider.notifier).acceptEdit(edit)`. Counter at top updates instantly.
- **Reject** → `rejectEdit(edit)`. Edit disappears from the list; V2 reverts that path to original. **No PDF render needed** for reject.
- **Header**: `"{accepted}/{total} accepted"` + bulk **Accept all** / **Reject all** actions.
- **Sticky bottom CTA**: `"Apply N edits → render tailored PDF"`. Only enabled when `acceptedPaths.isNotEmpty`. Tapping fires `apply_resume_edits` via the chat controller (so the agent loop resumes with the new `tailored_resume_id`).
- **Empty-after-resolve state**: if user resolved every edit but `acceptedPaths.isEmpty`, show "No changes accepted — original resume kept" + Back to chat. **Do not** call `apply_resume_edits`.

### 3. Decision card in chat stream (~1h)
When the `tailor_resume` tool result block lands in the chat ListView, render
a compact card: **"{N} proposed edits for {Job Title} — Review"** → tap opens
the Resume Diff Page. Edit
[lib/features/agent_chat/presentation/widgets/agent_block_views.dart](../../lib/features/agent_chat/presentation/widgets/agent_block_views.dart).

The old v1.2 "Tailored {file} — Preview / Save / Discard" card is dead under
the diff model. Delete it.

### 4. Apply trigger handoff (~1h)
The "Apply N edits" button on the diff page calls a method on the chat
controller (owned by A) that emits a synthetic `apply_resume_edits` tool_use
with the accepted subset. Coordinate with A on the exact controller method
signature in week 1.

### 5. Live preview pane (stretch)
On tablet/web: split-screen, diff list left, ResumeJSON-rendered preview
right that updates as user accepts/rejects. On mobile: behind a "Preview"
tab. **Debounce render** — at most once per ~400ms, not on every tap.

### 6. Resume preview improvements (~1h)
When the local file is missing (different device), show a clear
"this resume isn't on this device" state with a re-upload button.

### 7. Tailor flow page (~30 min)
Wire [tailor_page.dart](../../lib/features/jobs/presentation/tailor_page.dart)
to *open the Resume Diff Page* when proposed edits land — not to render
a finished PDF.

### 8. Cross-platform check
iOS, Android, web. File issues against F for shell-layer bugs.

---

## Files you own

- [lib/features/resumes/presentation/](../../lib/features/resumes/presentation/) — all UI, including new `resume_diff_page.dart`
- [lib/features/resumes/state/resume_controller.dart](../../lib/features/resumes/state/resume_controller.dart) — as a Riverpod Notifier
- Decision card in [lib/features/agent_chat/presentation/widgets/agent_block_views.dart](../../lib/features/agent_chat/presentation/widgets/agent_block_views.dart) (just the card for tailor_resume results — don't touch other block renderers)
- [lib/features/jobs/presentation/tailor_page.dart](../../lib/features/jobs/presentation/tailor_page.dart) — wire only

**You do NOT touch:**
- `lib/features/resumes/services/*` or `models/*` — R1 owns
- `lib/data/firestore/resumes_repository.dart` — R1 owns
- Tool executors in `builtin_tools.dart` — R1 owns the resume tools
- App shell, settings, navigation — F owns

---

## You're done when

- After `tailor_resume` fires, the chat shows "{N} proposed edits — Review" → tapping opens the Resume Diff Page.
- Every edit has its own Accept/Reject pair. Accepting updates the "N/M accepted" counter (and, if preview is on, the rendered resume) instantly.
- Rejecting an edit removes it and reverts that field to original **instantly — no PDF render**.
- "Apply N edits" only enables when at least one edit is accepted. Tapping renders the tailored PDF and resumes the agent loop.
- User can close chat mid-loop → see notification → tap → open Diff Page from there.
- App looks correct on iOS and Android.

---

## Coordination handshakes — week 1

| Day | With | Decide |
|---|---|---|
| Day 1 | F | Riverpod Notifier pattern — wait for F's example, then follow it for `ResumeController` |
| Day 2 | R1 | Receive `ProposedEdit` model + `ResumeDiffService.applyEdits` signature. Until then, build against a fake-edits fixture |
| Day 2 | A | Agree on chat-controller method signature for dispatching `apply_resume_edits` |
| Day 3 | A | Agree on the agent block emitted when `tailor_resume` returns — what fields are in the block so your card renders cleanly |

---

## Common pitfalls

- **Don't compute V2 in widgets.** Always call `resumeProvider.notifier.acceptEdit()` so state stays single-source-of-truth.
- **Don't render the tailored PDF preview on every accept tap** — debounce, or render only on explicit Preview action.
- **Don't let "Apply N edits" be tappable** while `acceptedPaths` is empty.
- **Don't try to render the diff inside a notification card** — link out to the Diff Page.
- **Don't fork design-system widgets** — extend [lib/shared/widgets/](../../lib/shared/widgets/).
- **Don't add markdown rendering** to text blocks — agent doesn't emit markdown yet.

---

## Relevant contract sections

- [api-contract.md §1](../api-contract.md) — agent loop overview
- [api-contract.md §2.4](../api-contract.md) — `tailor_resume` (what your trigger receives)
- [api-contract.md §2.4b](../api-contract.md) — `apply_resume_edits` (what your CTA dispatches)
- [api-contract.md §3](../api-contract.md) — `users/{uid}/resumes`
- [api-contract.md §1 human-in-the-loop table](../api-contract.md)

---

## How to use this brief with your AI

Paste this whole file as your first message to Claude / ChatGPT / Copilot,
then ask:

> *"Read this brief. What should I start with?"*

The AI should suggest: stub a `ResumeState` class with a fake-edits fixture
so you can build the Diff Page UI in parallel with R1. Don't let it start
with the PDF render — that's R1's territory.
