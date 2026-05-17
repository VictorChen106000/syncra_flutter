# Role 3 — Backend: Agent Reasoning (you — team lead)

**Estimated:** 11-14 hours
**Branch suggestion:** `r3-agent`

---

## The 30-second context

Syncra is a Flutter AI career copilot. Stack: **Flutter + Firebase + Anthropic
Claude + JSearch + Gmail API**. No backend server. Demo target: June 16, 2026.

You own the **agent brain**. The tool-use loop is built. The tool registry is
built. 8 tools are registered. Your job is to **add 2 new tools** (one is the
"agent learns about you" feature that's the demo's headline), **refactor the
passive brief generator** to call the same `runAgent` loop instead of bypassing
it (locks in the "one agent, two triggers" architecture), and **tune the
prompts** so the agent picks tools well.

You're the team lead — when other roles have architectural questions, you're
the arbiter.

## What's already shipped in YOUR area

- **[lib/features/agent_chat/services/anthropic_chat_service.dart](../../lib/features/agent_chat/services/anthropic_chat_service.dart)**
  Full tool-use loop. POSTs messages + tool definitions to Anthropic. Parses
  `tool_use` content blocks. Dispatches to `ToolExecutor` (well, the
  registry). Handles `ask_user` by emitting `InputRequestBlock` and pausing on
  a `Completer<String>` that's resolved by the controller when the user
  submits.
- **[lib/features/agent_chat/tools/tool.dart](../../lib/features/agent_chat/tools/tool.dart)**
  + [tool_registry.dart](../../lib/features/agent_chat/tools/tool_registry.dart)
  Tool model with name, description, input schema, UI label, icon, executor.
- **[lib/features/agent_chat/tools/builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart)**
  8 tools registered. 5 real, 3 stubs (the stubs are Role 2's job to make real).
- **[lib/features/agent_chat/tools/anthropic_tool_calls.dart](../../lib/features/agent_chat/tools/anthropic_tool_calls.dart)**
  `AnthropicParaphraseService` for tailor + draft-email Claude calls.
- **[lib/features/agent/services/anthropic_service.dart](../../lib/features/agent/services/anthropic_service.dart)**
  Brief reasoner: scores jobs against a resume. Currently called directly by
  `PassiveAgentController` (you'll refactor this).
- **[lib/features/agent/state/passive_agent_controller.dart](../../lib/features/agent/state/passive_agent_controller.dart)**
  Owns the brief lifecycle (idle / scanning / matching / done / error).
  Currently bypasses the tool registry — you refactor it to call `runAgent`.

## What you need to build

In priority order.

### 1. `save_to_pipeline` tool (~1h)

The agent needs to write pipeline cards through the tool registry, not via
`PassiveAgentController` directly. This unlocks the refactor in Task 2.

In [builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart),
add a new `_registerSaveToPipeline(registry, pipelineRepo, jobsRepo)`
function. Spec is in
[api-contract.md §2.6b](../api-contract.md). Input: job_id, category,
match_score, agent_action, agent_justification, matched_skills,
missing_skills. Calls `PipelineRepository.createCard(...)` and returns
`{ card_id }`.

### 2. Refactor PassiveAgentController to call `runAgent` (~2-3h)

This locks in the "one agent, two triggers" architecture documented in
[api-contract.md §1](../api-contract.md).

In [passive_agent_controller.dart](../../lib/features/agent/state/passive_agent_controller.dart),
`runBrief()` currently calls `AnthropicService.scoreJobs` directly. Replace
with a call to `AnthropicChatService.runAgent` with a canned prompt:

```dart
final prompt = '''
Run my morning brief. Use search_jobs to find 5 fresh roles that match my
profile (use my role from users/me). For each, call match_jobs to score it,
then save_to_pipeline for the strongest 5. Return a one-sentence summary when
done.
''';
```

The agent will: `search_jobs` → `read_resume` → `match_jobs` → `save_to_pipeline` (×5).
Each step shows up as a tool block in the agent event stream (which Role 5
subscribes to for notifications). Same Anthropic loop. Same code path.

Keep the existing `_status` enum + activity feed for the morning brief page's
progress UI — but populate it from the agent's event stream instead of from
your own bespoke activity log.

### 3. `remember_fact` tool + `learned_facts/` collection (~3h)

**This is the demo's headline feature.** "The agent learns about you across
sessions."

Spec in [api-contract.md §2.6a](../api-contract.md). Steps:

a. Add `_registerRememberFact(registry, factsRepo)` in
   [builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart).
   Input: `topic` (slug), `detail` (1-2 sentences). Writes to
   `users/{uid}/learned_facts/{factId}`.

b. Create
   [lib/data/firestore/learned_facts_repository.dart](../../lib/data/firestore/learned_facts_repository.dart)
   with `createFact()`, `listFacts(uid)`, `watchFacts(uid)`. Mirror the
   pattern of `ApplicationsRepository`.

c. **Extend `read_resume`** in
   [builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart)
   (handler at ~line 130). After loading the resume JSON, also load
   `learned_facts/` for the user. Surface them in the tool result as
   `{ resume_json: {...}, learned_facts: [...] }` so Claude can use them.

d. Update the system prompt in
   [anthropic_chat_service.dart](../../lib/features/agent_chat/services/anthropic_chat_service.dart)
   to teach Claude:
   > "When the user answers an `ask_user` question with information that
   > would apply beyond the current task (skills they have, preferences,
   > experiences), call `remember_fact` to persist it. Check `learned_facts`
   > before asking — don't ask the user something they've already told you."

### 4. Expose the agent event stream for FE5's notifications inbox (~1-2h)

Currently `AgentChatController` consumes the event stream privately. Role 5
needs to subscribe to the same stream from the notifications page.

Refactor: hoist the active stream up a level. Suggested pattern:

a. Create
   [lib/features/agent_chat/state/agent_event_bus.dart](../../lib/features/agent_chat/state/agent_event_bus.dart):
   ```dart
   class AgentEventBus extends ChangeNotifier {
     final _stream = StreamController<AgentEvent>.broadcast();
     Stream<AgentEvent> get events => _stream.stream;
     void add(AgentEvent e) => _stream.add(e);
     // ... dispose
   }
   ```

b. Provide `AgentEventBus` at the top of the widget tree (in
   [lib/app.dart](../../lib/app.dart)).

c. `AnthropicChatService.runPrompt` now writes events to BOTH its returned
   stream AND the bus.

d. Role 5 reads from `AgentEventBus` to populate the notifications inbox.

Tell Role 5 the bus's API in week 1.

### 5. Prompt + tool description tuning (~3-4h, iterative)

The agent's quality depends on these. Test against 10 canonical demo prompts
and tune:

**Demo prompts to test:**
1. "Help me apply to a UX role at an AI startup"
2. "Find me Singapore-based remote engineering jobs"
3. "Tailor my resume for the Linear UX designer position"
4. "Draft a cold email to Linear's design lead"
5. "I want to apply somewhere good" (vague — should trigger ask_user)
6. "What jobs am I currently a strong match for?"
7. "Send my application to TechFlow"
8. "Show me jobs that need Python skills"
9. "I have experience leading A/B tests — remember that"
10. "Apply to a senior backend role using my tailored resume"

For each:
- Run the prompt.
- Note: did Claude pick the right tools? Did it use `ask_user` when stuck?
  Did `remember_fact` fire when appropriate?
- Tune the system prompt or the relevant tool's `description` until the
  behavior matches what you'd want.

### 6. Loop safety nets + ask_user discipline (~1-2h)

Two small tweaks:

a. **Loop safety** — current limit is 8 iterations
   ([anthropic_chat_service.dart](../../lib/features/agent_chat/services/anthropic_chat_service.dart)
   constant `_maxLoopIterations`). When hit, current behavior emits a generic
   "I got stuck" message. Better: emit a message specific to the most recent
   failed tool ("I kept hitting errors on search_jobs — your JSearch quota
   may be out").

b. **`ask_user` discipline** — modify the `ask_user` tool description (built
   into [tool_registry.dart](../../lib/features/agent_chat/tools/tool_registry.dart)
   as `ToolRegistry.askUserTool`) to require Claude to provide 2-3 suggestion
   chips unless the question is genuinely open-ended.

## Files you own

```
lib/features/agent_chat/                    ← whole module
├── services/
│   ├── agent_service.dart                  ← interface, may add provideUserAnswer overrides
│   └── anthropic_chat_service.dart         ← system prompt + loop safety
├── tools/
│   ├── builtin_tools.dart                  ← add save_to_pipeline + remember_fact + extend read_resume
│   ├── anthropic_tool_calls.dart           ← paraphrase service (light edits if any)
│   ├── tool.dart                            ← model (unlikely to change)
│   └── tool_registry.dart                  ← ask_user tool description tuning
└── state/
    ├── agent_chat_controller.dart
    └── agent_event_bus.dart                ← CREATE

lib/features/agent/                         ← passive brief
├── services/anthropic_service.dart         ← brief-scoring prompts
├── state/passive_agent_controller.dart     ← REFACTOR to call runAgent
└── data/fake_resume.dart                   ← may delete once remember_fact lands

lib/data/firestore/learned_facts_repository.dart   ← CREATE
```

## You're done when

- Vague prompts ("help me find a job") trigger `ask_user` with 2-3 helpful
  chips, not random tool fires.
- "Apply to Linear with my tailored resume" produces the full chain:
  `search_jobs` → `read_resume` → `match_jobs` → `tailor_resume` → `draft_email`
  → `ask_user` ("send to careers@linear.com?") → done.
- Telling the agent something about yourself ("I led A/B tests at Acme")
  persists to `learned_facts`. Starting a new chat the next day, when
  tailoring for a role mentioning A/B testing, the agent uses the Acme detail
  without asking again.
- The morning brief produces real pipeline cards via `save_to_pipeline`,
  visible in `users/{uid}/pipeline/` in Firestore Console.
- Role 5's notifications inbox subscribes to your event bus and shows live
  tool calls.

## Coordination handshakes — week 1

| Handshake | With | Lock in week 1 |
|---|---|---|
| Agent event bus API | Role 5 | Suggested: `AgentEventBus.events` (Stream), `addListener` for notification entries |

## Common pitfalls

- **Don't tune by feel alone.** Keep the 10 demo prompts as a regression
  suite. Test before/after every prompt change.
- **Don't add new tools without updating** [api-contract.md §2](../api-contract.md).
- **Don't increase `_maxLoopIterations` past 10** without thinking about cost.
- **Set a monthly Anthropic spend cap of $5** in the console.
- **Don't break the `provideUserAnswer` contract.** Mock service must also
  override it (currently no-op).

## Relevant contract sections (read all of these)

- [api-contract.md §1 Agent loop](../api-contract.md) — the one-agent-two-triggers model
- [api-contract.md §2 Tools registry](../api-contract.md) — your tool specs (esp. §2.6a, §2.6b)
- [api-contract.md §3 Firestore data model](../api-contract.md) — learned_facts collection
- [api-contract.md §6 Security & rules](../api-contract.md) — key delivery + spend caps

## How to use this brief with your AI

Paste this entire file as your first message to Claude / ChatGPT / Copilot.
Then ask:

> *"Read this brief. I'm the team lead on Role 3. What architectural sequence
> should I follow — refactor first then add tools, or add tools first then
> refactor?"*

The answer is: tools first (Task 1 `save_to_pipeline`), then the refactor
(Task 2 — depends on save_to_pipeline existing). Then `remember_fact` (Task 3
— independent). Then the event bus (Task 4). Then tuning (Tasks 5-6, iterative).
