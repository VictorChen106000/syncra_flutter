# Role 5 — Frontend: Chat Surfaces, Email Modal & Notifications Inbox

**Estimated:** 14-18 hours
**Branch suggestion:** `r5-surfaces`

---

## The 30-second context

Syncra is a Flutter AI career copilot. Stack: **Flutter + Firebase + Anthropic
Claude + JSearch + Gmail API**. No backend server. Demo target: June 16, 2026.

You own **everything the user sees of the agent**: the chat, the inline
decision cards, the email review modal that gates email sending, and the
**notifications inbox** that lets users walk away from the chat while the
agent keeps working.

The chat works. You polish it. You build the two new pieces (email review
modal + notifications inbox upgrade) that are the highest-leverage UI work in
the project.

## What's already shipped in YOUR area

- **[lib/features/agent_chat/presentation/ai_chatbot_page.dart](../../lib/features/agent_chat/presentation/ai_chatbot_page.dart)** —
  chat page works end-to-end.
- **[lib/features/agent_chat/presentation/widgets/agent_block_views.dart](../../lib/features/agent_chat/presentation/widgets/agent_block_views.dart)** —
  renders each `AgentBlock` type:
  - `TextBlockView` ✅
  - `ThinkingBlockView` ✅
  - `ToolCallBlockView` ✅ (spinner → checkmark + result summary)
  - `ActionProposalView` ✅ (Accept / Make changes)
  - `InputRequestView` ✅ (text field + suggestion chips — needs polish)
- **[lib/features/agent_chat/presentation/widgets/chat_input_bar.dart](../../lib/features/agent_chat/presentation/widgets/chat_input_bar.dart)** —
  chat input.
- **[lib/features/agent_chat/presentation/widgets/agent_turn_view.dart](../../lib/features/agent_chat/presentation/widgets/agent_turn_view.dart)** —
  groups blocks into a turn.
- **[lib/features/resumes/presentation/resume_preview_page.dart](../../lib/features/resumes/presentation/resume_preview_page.dart)** —
  reads local file via `SfPdfViewer.file`. Works.
- **[lib/features/jobs/presentation/tailor_page.dart](../../lib/features/jobs/presentation/tailor_page.dart)** —
  exists as UI only. **Not wired to the real tailor service.** You wire it.
- **[lib/features/notifications/](../../lib/features/notifications/)** —
  exists as a static list using fixtures. **You rewrite it as a live agent-event
  inbox.**

## What you need to build

In priority order.

### 1. Notifications inbox upgrade (~5h, the most important piece)

**The walk-away pattern.** When the user closes the chat mid-loop, agent
events show up here with inline actions — accept, edit, or answer follow-up
questions WITHOUT reopening the chat.

a. **Subscribe to Role 3's `AgentEventBus`** (Role 3 builds this in week 1 —
   coordinate on the API).
   The bus emits the same `AgentEvent`s the chat consumes: `BlockAdded`,
   `ToolCallCompleted`, `TurnCompleted`.

b. **Translate events into NotificationEntry items**:
   - `BlockAdded(InputRequestBlock)` → entry with text field inline
   - `BlockAdded(ActionProposalBlock)` → entry with Accept / Make Changes buttons
   - `BlockAdded(TextBlock)` → entry with text + "Open chat" link
   - `ToolCallCompleted` → entry with the tool's result summary

c. **Rewrite [lib/features/notifications/state/notifications_controller.dart](../../lib/features/notifications/state/notifications_controller.dart)**:
   - Drop the fixture list.
   - Subscribe to `AgentEventBus.events`.
   - Maintain a list of `NotificationEntry` items.
   - Filter out entries the user has already acted on.

d. **Rewrite [lib/features/notifications/presentation/notifications_page.dart](../../lib/features/notifications/presentation/notifications_page.dart)**:
   - Each entry renders inline — text field for `ask_user`, decision buttons
     for proposals.
   - Tapping submit on a text field → `agentChatController.submitInputAnswer(blockId, answer)`
     (the controller resumes the agent loop).
   - Tapping accept → `agentChatController.acceptProposal(blockId)`.

e. **Demo flow to test:**
   1. Type "apply to Linear" in chat.
   2. Agent starts tool chain → fires `ask_user("which resume?")`.
   3. **Close the chat.** Go to notifications.
   4. See the `ask_user` entry. Type your answer in the inline text field.
   5. Agent loop resumes. New tool calls fire as notification entries.
   6. Eventually a `draft_email` result lands as a notification → tap "Send" →
      opens email review modal (Task 3).

### 2. Decision cards after tool results (~2-3h)

When the agent calls `tailor_resume` and the result is `{ tailored_resume_id,
file_name }`, render a card in the chat with:

- Title: "Tailored {file_name}"
- Preview button → opens
  [resume_preview_page.dart](../../lib/features/resumes/presentation/resume_preview_page.dart)
- Save button (default) → keeps it in the resume list
- Discard button → calls `resumeController.deleteResume(id)`

This is similar to `ActionProposalBlock` but specific to tailor results. Add
a new block type `TailorResultBlock` to
[agent_block.dart](../../lib/features/agent_chat/models/agent_block.dart) +
its renderer in
[agent_block_views.dart](../../lib/features/agent_chat/presentation/widgets/agent_block_views.dart).

In [builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart),
the `tailor_resume` handler should emit a `TailorResultBlock` (via the agent
event stream) instead of just returning the tool result silently. Coordinate
with Role 3 if needed.

### 3. Email review modal (~4h, gates all email sending)

**Create [lib/features/email/presentation/email_review_page.dart](../../lib/features/email/presentation/email_review_page.dart).**

Shown when the agent has drafted an email and is ready to send. Modal sheet
with:

- Subject (editable `TextField`)
- Body (editable `TextField`, multi-line, expandable)
- Recipient (editable `TextField`)
- Attached resume preview (thumbnail + filename)
- Two buttons: **Cancel** (closes modal) and **Send to {recipient}** (the
  destructive one, styled prominently)

**Critical: the modal is the only path that calls `send_email`.** Tapping Send:

a. Generate a one-shot UUID (`confirmation_token`).
b. Store it in an `EmailGateService` (in-memory map keyed by token).
c. Invoke the agent's `send_email` tool with the token + the (possibly
   edited) subject/body/recipient.

Coordinate with Role 2 on the token shape — they'll validate the token in
their `send_email` handler.

### 4. `InputRequestView` polish (~1h)

[InputRequestView in agent_block_views.dart](../../lib/features/agent_chat/presentation/widgets/agent_block_views.dart)
works but isn't polished. Make:

- The text field expansion smoother (animate height when content grows).
- Suggestion chips beautiful — same style as the rest of the app's pill
  buttons.
- "Answered" state distinct — show the user's answer in a subtle box, with a
  small "Edit" affordance.

### 5. Wire `tailor_page.dart` to the real tailor flow (~2h)

[lib/features/jobs/presentation/tailor_page.dart](../../lib/features/jobs/presentation/tailor_page.dart)
is currently UI only — there are 0 references to `tailorForJob`/`orchestrator`
in the file.

Wire it up:
- When the user taps "Tailor for {job}" from tailor_page (not via chat):
  - Call `agentChatController.sendPrompt(prompt: "Tailor my resume for ${job.id}")`.
  - Show progress states: "Reading resume", "Tailoring", "Rendering PDF"
    (these map to tool blocks fired by the agent).
  - On completion, navigate to the resume preview of the new tailored PDF.

This gives users a non-chat path to tailoring for users who landed on a job
directly.

### 6. Resume preview "not on this device" state (~1h)

When `ResumeFile.path` is null or the local file is missing (different
device), the preview currently shows a generic placeholder. Make it explicit:

- Big icon + headline: "This resume isn't on this device"
- 1-line explanation: "Files are stored locally. Re-upload from this device
  to view."
- Button: "Upload again" → opens file picker (calls
  `resumeController.pickAndUploadResumes`).

### 7. Cross-platform check (~2-3h, last week)

Run on iOS, Android, web. Document differences in a shared note. File
specific bugs against the owning role (e.g. layout bugs against FE1, agent
behavior against B3).

## Files you own

```
lib/features/agent_chat/presentation/        ← chat UI
├── ai_chatbot_page.dart                     ← polish
└── widgets/
    ├── agent_block_views.dart               ← + decision cards + InputRequestView polish
    ├── agent_turn_view.dart
    ├── chat_input_bar.dart
    └── chat_message_bubble.dart

lib/features/agent_chat/models/agent_block.dart  ← may add TailorResultBlock
lib/features/agent_chat/state/agent_chat_controller.dart  ← coordinate w/ Role 3

lib/features/notifications/                  ← REWRITE state + page
├── state/notifications_controller.dart      ← subscribe to AgentEventBus
└── presentation/notifications_page.dart     ← inline actions per entry

lib/features/email/                          ← CREATE folder
├── services/email_gate_service.dart         ← create (token store)
└── presentation/email_review_page.dart      ← create (the modal)

lib/features/resumes/presentation/resume_preview_page.dart  ← "not on this device" state
lib/features/jobs/presentation/tailor_page.dart             ← wire to real tailor
```

## You're done when

- The chat looks beautiful — `ask_user`, tool blocks, decision cards all feel
  consistent.
- **Walk-away test:** type "apply to Linear" → close the chat → notification
  appears with `ask_user` text field → answer it inline → agent continues →
  tailor result appears as a notification → tap → preview → save.
- Email review modal exists, subject/body editable. The Send button is the
  ONLY path to a real email going out.
- Tailor flow page works without going through the chat.
- App looks correct on iOS and Android.

## Coordination handshakes — week 1

| Handshake | With | Lock in week 1 |
|---|---|---|
| AgentEventBus API | Role 3 | Agree on `Stream<AgentEvent>` shape + which events are inbox-worthy |
| send_email confirmation token | Role 2 | One-shot UUID, generated by your modal, validated by their tool. Pick a shape (suggested: `String`) and stick to it. |

## Common pitfalls

- **Don't bypass the review modal for `send_email`.** The whole point of
  that modal is "the user explicitly tapped Send." If you let any path skip
  it, you've broken the trust model.
- **Don't render markdown in text blocks** unless Role 3 says the agent
  emits markdown. Right now it doesn't.
- **Don't fork the design-system widgets** — extend the ones in
  [lib/shared/widgets/](../../lib/shared/widgets/).
- **Test the walk-away flow on a real device.** Simulator behavior with
  notifications can mislead you.
- **Notifications page is the highest-risk new feature.** Build the
  subscription wiring first, even if the UI is rough — get the data flow
  right before the polish.

## Relevant contract sections

- [api-contract.md §1 Agent loop](../api-contract.md) — events route to both
  chat AND notifications
- [api-contract.md §2.5 draft_email](../api-contract.md) — the draft you
  receive
- [api-contract.md §2.8 send_email](../api-contract.md) — what your modal
  triggers (with confirmation)
- [api-contract.md §9 In-scope additions](../api-contract.md) — notifications
  inbox is explicitly in scope

## How to use this brief with your AI

Paste this entire file as your first message to Claude / ChatGPT / Copilot.
Then ask:

> *"Read this brief. I'm Role 5. The notifications inbox is the most novel
> piece — walk me through the architecture before I touch code. How does an
> agent event become a notification entry, and how does the user's tap in
> the notification resume the agent loop?"*

The AI will explain the event-bus subscription pattern + the controller
hand-off. That mental model is the most important thing to get right before
you start typing.
