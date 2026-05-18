# Role 4 — App Shell & Frontend Foundation (F)

**Track:** F — App Shell
**Estimated hours:** ~14h
**Demo day:** 2026-06-16

---

## The 30-second context

Syncra is a Flutter + Firebase career-agent app. You own the *shell* — the
stuff that makes it feel like a product instead of a tech demo. Navigation,
auth, dashboard, settings, applications page, notifications inbox UI, the
Riverpod state framework everyone else builds on, and the design system.

You're also the team's state-management foundation: you migrate the codebase
from `provider` → `flutter_riverpod` and publish the Notifier pattern that R2
and A follow for their own controllers.

Stack: Flutter, `flutter_riverpod` (replacing `provider`), `go_router`,
Firebase Auth + Firestore.

---

## What's already shipped in YOUR area

| Piece | Status |
|---|---|
| Google Sign-In via Firebase Auth | ✅ |
| Firestore migration + owner-only rules | ✅ |
| User doc creation on sign-in | ✅ |
| Splash, login, signup, onboarding (theatrical) | 🟡 — onboarding is fake, persists nothing |
| Dashboard with prompt entry + agent card stack | 🟡 — send button is broken (teleports w/o sending), Approval Pipeline count is hardcoded |
| Profile page | 🟡 — bare scaffold, needs real settings |
| Applications page (tracker) | ⚠️ — uses old multi-stage status enum, needs activity-log refactor |
| Notifications page | 🟡 — static fixtures, needs live event-stream wiring |
| Design-system primitives | ✅ |

---

## What you need to build

### 1. Riverpod migration framework (~4h) — DAY 1
Land in **one PR**. A half-migrated codebase with both `provider` and
`flutter_riverpod` is a debugging nightmare.

- Add `flutter_riverpod` to [pubspec.yaml](../../pubspec.yaml); remove `provider`.
- [lib/app.dart](../../lib/app.dart) becomes a `ProviderScope`.
- Convert these controllers to `Notifier<T>` with **immutable** state classes (use `List.unmodifiable`, freeze-style copy):
  - `AuthController`
  - `ApplicationsController`
  - `JobsController`
  - `NotificationsController`
- Publish your pattern as a one-page example. R2 follows it for `ResumeController`; A follows it for `AgentChatController` and `PassiveAgentController`.
- Replace `Consumer<X>` / `context.read<X>()` with `ref.watch(xProvider)` / `ref.read(xProvider.notifier)`.

### 2. Onboarding capture (~2h) — actually persist this time
[lib/features/auth/presentation/onboarding_page.dart](../../lib/features/auth/presentation/onboarding_page.dart)
is currently a scripted movie with hardcoded user messages. Replace with a
real capture flow:

- Capture `role` (free text, e.g. *"Senior UX Designer"*). Persist to `users/{uid}.role` via a new `UserRepository.update()` method (add it to [user_repository.dart](../../lib/data/firestore/user_repository.dart)).
- **Don't** capture `autonomy_level` here — defer to Settings. The user has no context to choose it yet.

### 3. Dashboard "Run today's brief" CTA (~1h)
Prominent button or card that calls
`ref.read(passiveAgentProvider.notifier).runBrief()`. Show last-run timestamp
("Last brief: 2 hours ago") so the user knows whether to tap again.

**Do not auto-fire on app open.** This is the v1.2 → v1.3 fix that protects
token spend. Hide the CTA when `users/{uid}.morning_brief_enabled == false`
(default).

### 4. Fix the dashboard prompt-entry send (~1h)
[dashboard_page.dart:840](../../lib/features/dashboard/presentation/dashboard_page.dart#L840)
currently just navigates to chat without dispatching the typed prompt. Fix it
to `ref.read(agentChatProvider.notifier).sendPrompt(prompt: text)` THEN
navigate. Coordinate with A on the controller method name post-Riverpod.

Also fix [dashboard_page.dart:281](../../lib/features/dashboard/presentation/dashboard_page.dart#L281)
— `Approval Pipeline` count is hardcoded `4`. Wire to a real source.

### 5. Settings page (~3h)
Replace [profile_page.dart](../../lib/features/profile/presentation/profile_page.dart):

- **Autonomy slider** — `suggest` / `ask_first` / `auto_apply`, default `ask_first`.
- **Morning brief toggle** — off by default. When on, dashboard shows the "Run today's brief" CTA. Even when on, still requires a tap to fire.
- Sign out, delete account.
- Persist all settings to `users/{uid}` via `UserRepository.update()`.

### 6. Applications page activity-log refactor (~4–5h)
[applications_page.dart](../../lib/features/applications/presentation/applications_page.dart)
still uses `viewed / replied / interview / offer / rejected` enum and a
5-stage progress bar. Per [api-contract.md §3](../api-contract.md), drop all
that. New schema:
- `drafted_at`, `sent_at` (Timestamps)
- `got_reply` (user-flippable bool)
- `follow_up_at` (Timestamp?)
- `notes`

Rebuild as a date-sorted activity log with a "Got a reply" switch per entry.
Filter chips become `All / Drafts / Sent / Replied`. Coordinate with
[ApplicationsController](../../lib/features/applications/state/applications_notifier.dart)
and [ApplicationsRepository](../../lib/data/firestore/applications_repository.dart).

### 7. Notifications inbox upgrade (~3–4h)
[notifications_page.dart](../../lib/features/notifications/presentation/notifications_page.dart)
is currently static fixtures. Rewrite as a live subscription on A's
`Stream<AgentEvent>` (you'll get the shape from A in week 1).

Each `ask_user` or tool-completion event that fires while user isn't on chat
becomes an inbox entry. Tapping an entry shows the inline surface
(text field for `ask_user`, or deep-link back into chat scrolled to the
`ProposedEditsBlock` for `tailor_resume` results — don't render the diff
inside the notification).

### 8. Empty states everywhere (~2h)
- First-time user with no resume — explain + one-tap upload action.
- No jobs in pipeline — explain + "Run today's brief" CTA.
- No applications — explain + "Open chat" CTA.

### 9. Bug-fixes the professor would catch
- `dashboard_page.dart:73` — hardcoded `'Daryn'` fallback. Replace with `''` or `'there'`.
- Chat header dead controls (`ai_chatbot_page.dart:159-176`) — either wire the "expand_more" and "edit_square" buttons or remove them.
- `_AgentLiveBanner` always shows live dot — gate on actual agent activity.

### 10. README setup section (~30 min)
List every `--dart-define` flag, where each key comes from, and one working
`flutter run` command. Saves your teammates 30 min each.

---

## Files you own

- [lib/core/router/](../../lib/core/router/)
- [lib/app.dart](../../lib/app.dart)
- [lib/features/auth/](../../lib/features/auth/)
- [lib/features/dashboard/](../../lib/features/dashboard/)
- [lib/features/profile/](../../lib/features/profile/)
- [lib/features/applications/](../../lib/features/applications/)
- [lib/features/notifications/](../../lib/features/notifications/) — UI only; A owns the event source
- [lib/shared/widgets/](../../lib/shared/widgets/)
- [lib/data/firestore/user_repository.dart](../../lib/data/firestore/user_repository.dart) (add `update()`)
- [pubspec.yaml](../../pubspec.yaml), [README.md](../../README.md), build config
- Firebase Auth config (you coordinate with I when they add Gmail scope)

**You do NOT touch:**
- Resume features — R1 / R2 own
- Agent loop / prompts / tools — A owns
- JSearch / Gmail / email modal — I owns

---

## You're done when

- `provider` is removed from pubspec; all listed controllers are Riverpod Notifiers returning immutable state.
- A brand-new user: signs in → captures `role` → lands on dashboard → sees "Run today's brief" CTA that does nothing until tapped → onboarding does not silently spend Claude tokens.
- Settings page exists; morning-brief toggle and autonomy slider both work and persist.
- Applications page renders as a date-sorted activity log with the new schema.
- Notifications page is live (subscribed to A's event stream), not fixtures.
- Every list screen has a beautiful empty state.
- README has a working "how to run this app" section.
- The 4 professor-bait bugs in §9 are gone.

---

## Coordination handshakes — week 1

| Day | With | Decide |
|---|---|---|
| Day 1 | R2, A | Publish your Riverpod Notifier pattern. R2 and A convert their controllers following it. |
| Day 2 | I | Gmail OAuth scope addition to Google Sign-In config (`https://www.googleapis.com/auth/gmail.send`) |
| Day 3 | A | `PassiveAgentController.runBrief()` signature for your "Run today's brief" button |
| Day 3 | A | `AgentEvent` stream shape for your notifications inbox |

---

## Common pitfalls

- **Don't half-migrate.** One PR for the Riverpod conversion.
- **Don't expose mutable lists/maps in state classes.** Use `List.unmodifiable` or freeze-style copy. Mutation breaks Riverpod's diffing.
- **Don't compute V2 in widgets** (this is R2's pitfall too but applies if you touch resume state).
- **Don't bring back the 24h auto-brief** as a "convenience." Token-cost regression.
- **Don't break the `go_router` redirect logic** — it handles auth-gating.
- **Don't add a new top-level dependency** without team vote.

---

## Relevant contract sections

- [api-contract.md §0](../api-contract.md) — locked decisions
- [api-contract.md §1](../api-contract.md) — agent loop (two user-initiated triggers; the "Run today's brief" button is *your* trigger)
- [api-contract.md §3 users/{uid}](../api-contract.md) — `morning_brief_enabled`, `autonomy_level`, `last_brief_at` (display-only)
- [api-contract.md §3 applications](../api-contract.md) — new activity-log schema
- [api-contract.md §6](../api-contract.md) — security rules
- [api-contract.md §9](../api-contract.md) — in-app notifications inbox spec

---

## How to use this brief with your AI

Paste this whole file as your first message to Claude / ChatGPT / Copilot,
then ask:

> *"Read this brief. What should I start with?"*

The AI should suggest: the Riverpod migration first (day 1 unblocks
everyone), then onboarding capture + Settings (so the morning-brief toggle
has somewhere to live), then the Applications refactor. Notifications inbox
last (depends on A's event stream).
