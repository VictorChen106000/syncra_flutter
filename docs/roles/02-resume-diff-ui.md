# Role 2 — Resume Diff UI (R2, Frontend)

**Track:** R2 — Resume Diff UI
**Estimated hours:** ~10–12h
**Demo day:** 2026-06-16
**Companion role:** R1 (Resume Engine) — you import their model + service

---

## The 30-second context

Syncra is a Flutter + Firebase career-agent app. The user lives in the chat —
they ask the agent to do things, attach their resume via the `+` button, and
see results inline. The headline demo moment is: the agent proposes a list
of targeted resume edits **right in the chat stream**, the user accepts or
rejects each one like a GitHub PR review, and the accepted subset becomes a
tailored PDF.

**The diff lives inside the chat — not on a separate page.** When
`tailor_resume` returns, your block renderer expands inline with each
ProposedEdit as a card. No navigation hop. The user never leaves the
conversation. The resume *list* page still exists for browsing original +
tailored PDFs, but it's the output viewer, not the review surface.

**You own:** the inline block renderer that displays proposed edits, the
Riverpod controller that holds V1/V2 state, and the resume list/preview UI.
R1 produces the data (proposed edits + the pure function that applies them);
A renders the rest of the chat stream and dispatches `apply_resume_edits` on
your block's behalf.

Stack: Flutter, Riverpod (replacing `provider`), strict immutable state.

---

## What's already shipped in YOUR area

| Piece | Status |
|---|---|
| `resume_lists_page.dart` — list of resumes | ✅ |
| `resume_preview_page.dart` — local PDF viewer | ✅ |
| `ResumeController` (Provider-based, wholesale shape) | ⚠️ — rewrite as Riverpod Notifier with diff state |
| `proposed_edits_block.dart` — inline chat block | ❌ — create (the headline build) |
| `tailor_page.dart` | 🟡 — drop or repurpose as the resume-list entry point (review now happens in chat) |

---

## What you need to build

### 1. ResumeController as Riverpod Notifier (~3h)
After F (App Shell) publishes the Riverpod pattern (day 1), convert
[lib/features/resumes/state/resume_notifier.dart](../../lib/features/resumes/state/resume_notifier.dart)
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

### 2. `ProposedEditsBlock` — inline in the chat (~5h) — THE HEADLINE BUILD
Create [lib/features/agent_chat/presentation/widgets/proposed_edits_block.dart](../../lib/features/agent_chat/presentation/widgets/proposed_edits_block.dart) (new file you own entirely — no collision with A's other block renderers).

In [agent_block_views.dart](../../lib/features/agent_chat/presentation/widgets/agent_block_views.dart),
A adds a single `case ProposedEditsBlock` that delegates to your widget. You
write the widget; A wires the case.

Layout — the block renders inline in the chat ListView, between the agent's
text message and whatever comes next:

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
│  SKILLS                                        │
│  − React, JavaScript, Figma                    │
│  + React, TypeScript, Figma, Tailwind          │
│  💡 JD lists TypeScript + Tailwind as must-have│
│  [ Reject ]                  [ Accept ]        │
├────────────────────────────────────────────────┤
│  ... 3 more edits ...                          │
├────────────────────────────────────────────────┤
│      [ Apply N edits → render tailored PDF ]   │  ← sticky footer-in-block
└────────────────────────────────────────────────┘

[agent waits — no follow-up blocks until user resolves]
```

Wiring:
- **Per-card Accept** → `ref.read(resumeProvider.notifier).acceptEdit(edit)`. Header counter updates instantly.
- **Per-card Reject** → `rejectEdit(edit)`. Card collapses with a "rejected" badge; V2 reverts that path. **No PDF render.**
- **Header bulk actions** — Accept all / Reject all.
- **Footer CTA** — `"Apply N edits"` only enabled when `acceptedPaths.isNotEmpty`. Tapping calls A's chat controller method to dispatch `apply_resume_edits` with the accepted subset. The agent loop resumes; a new tool result block appears below: *"Tailored resume rendered → [View PDF]"*.
- **Empty-after-resolve state** — if user resolved all edits with zero accepted, show *"No changes accepted — original resume kept"* in the footer. Do **not** call `apply_resume_edits`.
- **Long lists** — if >5 edits, each card is collapsible (collapsed = just the section path; expanded = full diff). Keep the chat scrollable.

The old v1.2 "Tailored {file} — Preview / Save / Discard" decision card is dead under the diff model. Delete it.

### 3. Apply trigger handshake (~1h)
The footer CTA calls a method on the chat controller (owned by A) that emits
a synthetic `apply_resume_edits` tool_use with the accepted subset. Agree on
the exact controller method signature with A in week 1 — likely something
like `chatController.applyResumeEdits(resumeId, List<ProposedEdit>)`.

### 4. Live preview pane (stretch — tablet/web)
On tablet/web: when a `ProposedEditsBlock` is in the visible part of the
chat, optionally show a right-side preview pane with the ResumeJSON-rendered
V2 updating as the user accepts/rejects. On mobile, skip — the block is
already the review surface. **Debounce render** — at most once per ~400ms,
not on every tap.

### 5. Resume preview improvements (~1h)
The resume list page and `resume_preview_page.dart` still exist — they
display the original + any tailored PDFs after apply succeeds. When the local
file is missing (different device), show *"this resume isn't on this device"*
with a re-upload button.

### 6. Tailored-result link in chat (~30 min)
After `apply_resume_edits` succeeds, the tool result block in chat should
show: *"Tailored for {Job Title} — [View PDF]"*. Tapping opens
`resume_preview_page.dart` with the new tailored resume.

### 7. Cross-platform check
iOS, Android, web. File issues against F for shell-layer bugs.

---

## Files you own

- [lib/features/agent_chat/presentation/widgets/proposed_edits_block.dart](../../lib/features/agent_chat/presentation/widgets/proposed_edits_block.dart) (NEW — the inline diff block)
- [lib/features/resumes/presentation/](../../lib/features/resumes/presentation/) — resume list page, resume preview page (output viewers)
- [lib/features/resumes/state/resume_notifier.dart](../../lib/features/resumes/state/resume_notifier.dart) — as a Riverpod Notifier holding V1/V2/pending/acceptedPaths

**You do NOT touch:**
- [lib/features/agent_chat/presentation/widgets/agent_block_views.dart](../../lib/features/agent_chat/presentation/widgets/agent_block_views.dart) — A owns this file; they add one `case ProposedEditsBlock` that delegates to your widget
- `lib/features/resumes/services/*` or `models/*` — R1 owns
- `lib/data/firestore/resumes_repository.dart` — R1 owns
- Tool executors in `builtin_tools.dart` — R1 owns the resume tools
- App shell, settings, navigation — F owns

---

## You're done when

- After `tailor_resume` fires, the chat scrolls to show a `ProposedEditsBlock` inline — no navigation hop.
- Every edit has its own Accept/Reject pair. Accepting updates the header counter (and, if preview is on, the rendered resume) instantly.
- Rejecting an edit collapses it with a "rejected" badge and reverts that field to original **instantly — no PDF render**.
- The footer "Apply N edits" CTA only enables when at least one edit is accepted. Tapping renders the tailored PDF and the chat continues with a *"Tailored for X — [View PDF]"* result block.
- After apply, tapping "View PDF" opens `resume_preview_page.dart` showing the new tailored resume.
- User can close chat mid-loop → see notification → tap → return to chat scrolled to the same block.
- App looks correct on iOS and Android.

---

## Coordination handshakes — week 1

| Day | With | Decide |
|---|---|---|
| Day 1 | F | Riverpod Notifier pattern — wait for F's example, then follow it for `ResumeController` |
| Day 2 | R1 | Receive `ProposedEdit` model + `ResumeDiffService.applyEdits` signature. Until then, build against a fake-edits fixture |
| Day 2 | A | Agree on chat-controller method signature for dispatching `apply_resume_edits` (likely `applyResumeEdits(resumeId, List<ProposedEdit>)`) |
| Day 2 | A | Agree on the `ProposedEditsBlock` data shape — what `tailor_resume` tool result the chat parses into a block your widget renders. Also: A adds the `case ProposedEditsBlock` in `agent_block_views.dart` that delegates to your widget |

---

## Common pitfalls

- **Don't compute V2 in widgets.** Always call `resumeProvider.notifier.acceptEdit()` so state stays single-source-of-truth.
- **Don't render the tailored PDF preview on every accept tap** — debounce, or render only on explicit Preview action.
- **Don't let "Apply N edits" be tappable** while `acceptedPaths` is empty.
- **Don't try to render the diff inside a notification card** — deep-link back into chat at the `ProposedEditsBlock`.
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
so you can build the `ProposedEditsBlock` widget in parallel with R1. Don't let it start
with the PDF render — that's R1's territory.
