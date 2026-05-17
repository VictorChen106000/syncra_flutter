# Role 3 — Agent Reasoning (A, Backend)

**Track:** A — Agent Reasoning
**Estimated hours:** ~10–14h
**Demo day:** 2026-06-16

---

## The 30-second context

Syncra is a Flutter + Firebase career-agent app. There is **one** Claude agent
with one tool registry. The loop already works end-to-end (search → tailor →
draft → review). Your job is to make it *good*: tighten prompts so Claude
produces the diff-style edits R1/R2 need, refactor the passive controller so
it stops burning tokens on app open, and implement two new tools that make
the agent feel like it remembers and works ahead.

Stack: Flutter, Anthropic Claude (Haiku 4.5) direct from Flutter via
`anthropic-dangerous-direct-browser-access`.

---

## What's already shipped in YOUR area

| Piece | Status |
|---|---|
| `AnthropicChatService` with tool-use loop | ✅ |
| `ask_user` mid-flow input (text field in chat) | ✅ |
| Tool registry + 8 tools registered | ✅ (some stubs) |
| Brief reasoner (Claude scores jobs) | ✅ |
| `tailor_resume` prompt (wholesale rewrite) | ⚠️ — rewrite for diff model |
| `PassiveAgentController` 24h auto-fire | ⚠️ — remove (token cost) |
| `save_to_pipeline` tool | ❌ — implement |
| `remember_fact` tool + `learned_facts/` collection | ❌ — implement |
| AgentEvent stream for notifications inbox | ❌ — expose |

---

## What you need to build

### 1. Tighten the `tailor_resume` prompt (~2h)
In [anthropic_tool_calls.dart](../../lib/features/agent_chat/tools/anthropic_tool_calls.dart),
rewrite the prompt that produces `proposed_edits`. The model MUST:

- Return JSON only: `{ "proposed_edits": [ { target_path, original_text, proposed_text, reason } ] }`
- Quote `original_text` **verbatim** from the resume — R1 validates by string match and drops mismatches.
- Propose 3–8 edits max, prioritized by relevance to the JD.
- Never invent experience, employers, dates, metrics.
- Prefer rewriting individual bullets over full-section rewrites.
- Each `reason` is one sentence: *"Aligns with the JD's emphasis on growth metrics."*

Get R1 to validate the schema on day 1 — they enforce it post-response.

### 2. Tune the system prompt (~1h)
In [anthropic_chat_service.dart](../../lib/features/agent_chat/services/anthropic_chat_service.dart),
the `_system` constant. Add:

- *"When tailoring a resume, you propose changes — you never overwrite. The user reviews every edit before it lands."*
- *"Prefer calling tools over guessing. When stuck, use `ask_user` with 2–3 suggestion chips."*
- *"After `tailor_resume` returns, stop and wait — the user reviews the proposed edits in the diff viewer."*

### 3. Tool descriptions in `builtin_tools.dart` (~1h)
Each `description:` is what Claude reads when picking. Tight, behavioral,
clear about when NOT to use. Specifically:

- `tailor_resume`: *"Proposes targeted edits to the resume. Does not modify the resume. The user reviews each edit in a diff viewer before applying."*
- `apply_resume_edits`: *"Call only after the user has reviewed proposed edits. Input is the subset the user accepted in the diff viewer."*

### 4. Loop sequencing — wait after `tailor_resume` (~1h)
**Critical.** After `tailor_resume` returns proposed_edits, Claude must
**stop and wait** — do NOT auto-call `apply_resume_edits` or `draft_email`.
R2's diff viewer will dispatch `apply_resume_edits` with the accepted subset;
the resulting tool_result feeds back into the loop and Claude then proceeds
(typically to `draft_email`).

Test: vague user prompts that trigger tailor_resume should land in chat as
proposed_edits and *not* immediately fire follow-up tool calls.

### 5. `ask_user` discipline (~30 min)
Bake into the tool description: *"Always provide 2–3 suggestion chips unless the question is genuinely open-ended."*

### 6. Loop safety nets (~1h)
`_maxLoopIterations` stays at 8. Add a better recovery message when the loop
terminates due to repeated tool failures (not just hitting the iteration cap).

### 7. Refactor `PassiveAgentController` (~2h)
[passive_agent_controller.dart](../../lib/features/agent/state/passive_agent_controller.dart).

- **Remove the 24h auto-fire** on app open. Delete the timer / app-resume hook entirely.
- Expose `runBrief()` as a pure callable that F's "Run today's brief" dashboard button invokes.
- Internally call `AnthropicChatService.runAgent` with a canned brief prompt — same code path as user-typed prompts. Locks in "one agent, two triggers" where both are explicit user taps.
- Persist `last_brief_at` (for F's "Last brief: 2h ago" label) but **never read it to auto-fire**.

### 8. `save_to_pipeline` tool (~1h)
Per [api-contract.md §2.6b](../api-contract.md). Lets `runBrief()` persist
pipeline cards through the tool registry instead of bypassing it.

### 9. `remember_fact` tool + `learned_facts/` collection (~3h)
Per [api-contract.md §2.6a](../api-contract.md). When the user answers
`ask_user` with persistent info ("yes, I led A/B tests at Acme"), the agent
calls `remember_fact` to persist it. Extend `read_resume` to include
learned_facts in its output so future tailoring uses them.

Strong demo moment: *"The agent learned about you across sessions."*

### 10. Event-stream subscription for F's notifications inbox (~1–2h)
Expose `Stream<AgentEvent>` above the chat controller so both the chat UI
and F's notifications inbox can subscribe. Agree on `AgentEvent` shape with F
in week 1.

---

## Files you own

- [lib/features/agent_chat/services/anthropic_chat_service.dart](../../lib/features/agent_chat/services/anthropic_chat_service.dart) — the loop
- [lib/features/agent_chat/tools/anthropic_tool_calls.dart](../../lib/features/agent_chat/tools/anthropic_tool_calls.dart) — paraphrase + draft prompts
- [lib/features/agent_chat/tools/builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart) — system prompt + tool descriptions (NOT the resume tool executors — R1 owns those; NOT the integration tool executors — I owns those)
- [lib/features/agent/services/anthropic_service.dart](../../lib/features/agent/services/anthropic_service.dart) — brief reasoner
- [lib/features/agent/state/passive_agent_controller.dart](../../lib/features/agent/state/passive_agent_controller.dart) — now a callable
- [lib/features/agent_chat/state/agent_chat_controller.dart](../../lib/features/agent_chat/state/agent_chat_controller.dart) — chat controller (Riverpod Notifier, following F's pattern)

**You do NOT touch:**
- `tailor_resume` or `apply_resume_edits` executor bodies — R1 owns
- `search_jobs` or `send_email` executor bodies — I owns
- UI files — R2 / F own

---

## You're done when

- `tailor_resume` returns 3–8 ProposedEdit records, each with a verbatim `original_text`, on every test prompt. No full-section rewrites slip through.
- After `tailor_resume` fires, the agent waits — it does not auto-call `draft_email` until the user has resolved the diff viewer.
- Tapping F's "Run today's brief" button produces the brief flow that auto-fired in v1.2, but **only on explicit tap**. Nothing runs on app launch.
- Vague prompts trigger `ask_user` with suggestion chips, not random tool fires.
- `remember_fact` writes survive across app restarts and influence the next tailoring call.

---

## Coordination handshakes — week 1

| Day | With | Decide |
|---|---|---|
| Day 1 | R1 | Lock the `proposed_edits` JSON schema (you prompt, they validate) |
| Day 2 | R2 | Chat block shape for `tailor_resume` results + the controller method R2's "Apply N edits" CTA calls |
| Day 3 | F | `PassiveAgentController.runBrief()` signature (sync/async, return shape) |
| Day 3 | F | `AgentEvent` stream shape — what each event carries (kind, body, target route) |

---

## Common pitfalls

- **Don't let Claude call `apply_resume_edits` itself.** That tool is user-triggered via UI.
- **Don't let the `tailor_resume` prompt drift back to full-section rewrites.** Test weekly with a regression prompt set.
- **Don't reintroduce the 24h auto-fire** as a "small convenience." It's a token-cost regression that was the whole reason for the v1.3 refactor.
- **Don't tune by feel alone.** Keep 10 canonical demo prompts; test before and after every prompt change.
- **Don't add new tools** without updating [api-contract.md §2](../api-contract.md).
- **Don't increase `_maxLoopIterations` past 10** without cost review.

---

## Relevant contract sections (read these)

- [api-contract.md §0](../api-contract.md) — locked decisions
- [api-contract.md §1](../api-contract.md) — agent loop (two user-initiated triggers)
- [api-contract.md §2](../api-contract.md) — all tools
- [api-contract.md §2.4](../api-contract.md) — `tailor_resume` schema you must emit
- [api-contract.md §2.6a](../api-contract.md) — `remember_fact`
- [api-contract.md §2.6b](../api-contract.md) — `save_to_pipeline`
- [api-contract.md §5.1](../api-contract.md) — Anthropic endpoint config
- [api-contract.md §8](../api-contract.md) — rate limits & cost guards

---

## How to use this brief with your AI

Paste this whole file as your first message to Claude / ChatGPT / Copilot,
then ask:

> *"Read this brief. What should I start with?"*

The AI should suggest: tighten the `tailor_resume` prompt first (it unblocks
R1's validation and R2's UI), then the PassiveAgentController refactor (kills
the token burn), then the new tools.
