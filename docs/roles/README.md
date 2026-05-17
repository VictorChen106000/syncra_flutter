# Per-role briefs — Syncra demo (June 16, 2026)

Each `.md` file in this folder is a **self-contained brief for one person**.
Pick your role, open the file, paste the whole thing as the first message
to your AI assistant (Claude Code, ChatGPT, Copilot Chat, whatever), then ask:

> *"Read this brief. What should I start with?"*

Every brief tells the AI:
- What Syncra is and what's already shipped
- Your role's scope and the files you own (and don't)
- What you need to build (numbered, with file paths)
- Acceptance criteria
- Coordination handshakes with other roles (week 1)
- Common pitfalls
- Which contract sections to read

---

## The 5 roles (v1.3 — restructured 2026-05-17)

| File | Role | Owner | Hours |
|---|---|---|---|
| [01-resume-engine.md](./01-resume-engine.md) | **R1** — Resume Engine (backend, pure Dart) | Person 1 | ~8–10h |
| [02-resume-diff-ui.md](./02-resume-diff-ui.md) | **R2** — Resume Diff UI (frontend, PR-style viewer) | Person 2 | ~10–12h |
| [03-agent-reasoning.md](./03-agent-reasoning.md) | **A** — Agent Reasoning (Claude loop, prompts, brief refactor) | Person 3 (often team lead) | ~10–14h |
| [04-app-shell.md](./04-app-shell.md) | **F** — App Shell & Frontend Foundation (Riverpod, nav, settings, applications, notifications) | Person 4 | ~14h |
| [05-integrations.md](./05-integrations.md) | **I** — Integrations & Send (JSearch + Gmail + email review modal) | Person 5 | ~16–18h |

---

## Why the resume work is split across two people (R1 + R2)

The v1.3 pivot makes resume tailoring the highest-leverage demo moment AND
the largest body of work. Splitting it into engine (R1) and UI (R2) lets two
people ship in parallel without colliding on files.

**The contract between them is small and locked in week 1:**

```dart
// R1 SHIPS THESE — by end of day 2:
class ProposedEdit {
  final String targetPath, originalText, proposedText, reason;
}
class ResumeDiffService {
  static ResumeJSON applyEdits(ResumeJSON original, List<ProposedEdit> accepted);
}

// + tailor_resume and apply_resume_edits tool executors
```

R2 imports these, builds the inline `ProposedEditsBlock` + ResumeController state, never touches
R1's services. R1 ships nothing UI, never touches R2's presentation files.
After day 2, neither blocks the other.

**File ownership (the no-collision rule):**

| Files | R1 (Engine) | R2 (UI) |
|---|---|---|
| `lib/features/resumes/models/` | ✅ owns | imports |
| `lib/features/resumes/services/` | ✅ owns | imports `applyEdits` |
| `lib/data/firestore/resumes_repository.dart` | ✅ owns | imports |
| `lib/features/agent_chat/tools/builtin_tools.dart` — `tailor_resume` + `apply_resume_edits` executors | ✅ owns | does not touch |
| `lib/features/resumes/presentation/` (list page, preview page) | does not touch | ✅ owns |
| `lib/features/resumes/state/resume_controller.dart` (Riverpod Notifier, V1/V2 state) | does not touch | ✅ owns |
| `lib/features/agent_chat/presentation/widgets/proposed_edits_block.dart` (NEW — inline diff block) | does not touch | ✅ owns (whole file) |
| `lib/features/agent_chat/presentation/widgets/agent_block_views.dart` | does not touch | does not touch — A owns; A adds one `case ProposedEditsBlock` delegating to R2's widget |

**Why inline in the chat (not a separate page):** users live in the chat — they upload resumes there, talk to the agent there, and see results there. A separate "Resume Diff Page" forces a navigation hop out of the conversation. Rendering the diff as an inline block (like Claude artifacts) keeps the agent loop and the review in the same surface.

---

## Before you start — read these in order

1. [product-brief.md](../product-brief.md) — what Syncra is (~3 min)
2. [api-contract.md](../api-contract.md) — the technical spec (~10 min skim)
3. Your role file in this folder

If you want the bigger-picture team handoff with all 5 tracks side by side,
see [team-handoff.md](../team-handoff.md).

---

## The four critical handshakes (week 1)

Roles depend on each other in narrow, specific ways. Lock these in week 1 or
you'll deadlock late:

| Handshake | Between | Decide |
|---|---|---|
| `ProposedEdit` model + `ResumeDiffService` signatures | R1 → R2 | R1 ships stubs by end of day 2. R2 builds against fake fixture until then. |
| `tailor_resume` JSON schema | A ↔ R1 | A writes the prompt; R1 validates the parse. Lock the schema day 1. |
| OAuth scope + send-email confirmation token | I ↔ F + I ↔ A | F adds `gmail.send` to GoogleSignIn config; I + A agree on the one-shot UUID token shape. |
| Agent event stream | A → F | `Stream<AgentEvent>` exposed at provider level for F's notifications inbox. |

---

## What changed from the v1.2 brief set

Restructured 2026-05-17:

- **Resume work split into R1 (engine) + R2 (UI)** — was one role; two-person parallelism + the v1.3 diff-model rewrite justify the split.
- **`tailor_resume` is now a "PR diff" not a wholesale rewrite** — touches R1, R2, A. See [api-contract.md §2.4](../api-contract.md).
- **Morning brief no longer auto-fires every 24h** — touches A, F. See [api-contract.md §1](../api-contract.md).
- **Frontend uses Riverpod + immutable state** — F publishes the pattern; R2 + A follow it for their own controllers.
- **Email review modal moved from FE2 → I (Integrations)** — pairs send-gate UI with the send tool.
