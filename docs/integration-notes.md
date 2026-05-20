# Integration Notes — F (App Shell) → Teammates

Date: 2026-05-18
Branch: `daryn/frontend-final`

The F track landed Riverpod, settings/onboarding, the live notifications inbox,
and the applications activity-log refactor. Three contracts changed —
read your section if you own A, R2, or I.

---

## A — Agent Reasoning

### Agent reasoning update — 2026-05-20

Confirmed current behavior:

- `AgentChatNotifier` forwards agent events to `NotificationsNotifier`.
- `ToolCallCompleted(status: done)` and `InputRequestBlock` can surface in notifications.
- `PassiveAgentNotifier.runBrief()` now uses the same `AgentService` / tool-loop path as normal chat prompts when an Anthropic key is present.
- The old direct/mock brief path remains only as no-key fallback.
- `read_resume`, `match_jobs`, and `tailor_resume` can use attached `resume_id`.

### Firebase Storage note

Resume uploads now use Firebase Storage. Flutter Web requires CORS on the Storage bucket for parsing/preview downloads. iOS and Android do not require CORS, but all platforms require correct Storage security rules.

### What changed
`NotificationsNotifier` is no longer a fixture. It now exposes a public
method that ingests [`AgentEvent`](../lib/features/agent_chat/services/agent_service.dart):

```dart
// lib/features/notifications/state/notifications_notifier.dart
void onAgentEvent(AgentEvent event);
```

The forwarding is **already wired** for you, one line, in
[`AgentChatNotifier._handleEvent`](../lib/features/agent_chat/state/agent_chat_notifier.dart):

```dart
ref.read(notificationsProvider.notifier).onAgentEvent(event);
```

### What you need to know
- This fires on **every** agent event during a chat turn. Filtering is
  done inside the notifier via
  [`AppNotification.fromAgentEvent`](../lib/features/notifications/models/app_notification.dart)
  — which currently only surfaces:
  - `BlockAdded(InputRequestBlock)` → "Agent needs your input" intercept
  - `ToolCallCompleted(status: done)` → "Agent finished a task"

  Everything else (thinking blocks, text, `ToolCallCompleted` failures) is
  silently dropped.

- If you want to suppress notifications **while the chat page is the
  active route**, that's a TODO inside `onAgentEvent`. The brief asked for
  this but for v1 we always record so the bell badge stays meaningful.

- If you want to add new event types or new notification kinds, extend
  `AppNotification.fromAgentEvent` — UI handles whatever the model returns.

### What I need from you
- Sanity check: is firing `onAgentEvent` on every event OK, or would you
  rather emit notifications from your own layer (e.g. only when the agent
  loop ends, only for important tool calls)? If yes, remove the one-line
  forward in `_handleEvent` and call `onAgentEvent` from wherever fits.

---

## R2 — Resume Diff UI

### What changed
The applications schema was refactored. The
[`createApplication`](../lib/data/firestore/applications_repository.dart) signature is now:

```dart
// Before
applicationsRepo.createApplication(uid: ..., job: ..., status: JobStatus.submitted);

// After
applicationsRepo.createApplication(uid: ..., job: ..., resumeId: 'r123');
```

- The `status` param is **gone**. `JobStatus` enum is **deleted**.
- New applications start as **drafts** (`sent_at: null`).
- To mark sent, follow up with:
  ```dart
  await applicationsRepo.markSent(uid, appId);
  ```

### What you need to know
- After the user accepts a `ProposedEditsBlock` and `apply_resume_edits`
  renders the PDF, when you call `createApplication` to record the tracker
  entry: pass the new tailored resume's id via `resumeId:`. This wires the
  application → resume link expected by the API contract (§3 `resume_id`).
- If your flow includes a "Send now" affordance, call `markSent` from the
  applications notifier:
  ```dart
  ref.read(applicationsProvider.notifier).markSent(appId);
  ```

### What I need from you
- Confirm your apply-edits flow still works end-to-end. If you were
  reading `TrackedApplication.status` or `.lastUpdate` anywhere, those
  fields are gone — use `phase`, `sentAt`, `draftedAt` instead.

---

## I — Integrations (Gmail)

### What changed
Same applications-schema refactor. The agent tool
[`send_email`](../lib/features/agent_chat/tools/builtin_tools.dart) should no
longer write to `status: 'submitted'`. It should call:

```dart
await applicationsRepo.markSent(uid, appId, sentEmailId: gmailMessageId);
```

This stamps `sent_at` and persists the Gmail message id in the new
`sent_email_id` field per [api-contract.md §3](api-contract.md).

### Also relevant
The `save_to_tracker` tool now has an optional `mark_sent: bool` arg
instead of a `status` enum. When the agent is in `auto_apply` mode and
`send_email` succeeds, the agent should call `save_to_tracker` with
`mark_sent: true`. In `ask_first` mode, save as draft (`mark_sent: false`
or omitted), then the user taps **Mark as sent** in the tracker.

### What I need from you
- After Gmail OAuth scope is added and `send_email` actually sends,
  update its handler to call `markSent` with the message id.
- Confirm the OAuth scope addition (`gmail.send`) doesn't break the
  existing Google Sign-In flow.

---

## Shared changes (FYI)

These don't need action from you but you'll see them in the diff:

- **Reduced-motion guard**: animations now respect
  `MediaQuery.disableAnimations` via
  [`lib/core/utils/motion.dart`](../lib/core/utils/motion.dart). If you
  add `.animate().repeat()` anywhere, use
  `repeatIfMotion(context)` instead of `(c) => c.repeat()`.
- **Semantics labels**: icon-only buttons now have `Semantics` /
  `tooltip` for screen readers. Follow the same pattern in new UI.
- **Font weights**: theme defaults toned down (titles `w700`, body
  `w500-w600`). If you've been hardcoding `FontWeight.w900` inline, that
  still works — but consider using the theme.

---

## Quick verification commands

```bash
flutter analyze lib/                    # should be 3 pre-existing infos
flutter run --dart-define=ANTHROPIC_API_KEY=sk-ant-...
```

End-to-end demo flow:
1. Fresh sign-in → onboarding → dashboard
2. Profile → toggle morning brief → dashboard → "Run today's brief"
3. Pipeline populates → approve a job → tracker shows it as **Sent**
4. Open chat → send a prompt → bell badge increments → tap bell → entries are there

If anything's off, ping me in Slack.
