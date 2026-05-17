# Role 4 — Frontend: Shell, Onboarding & Applications page

**Estimated:** 14-17 hours
**Branch suggestion:** `r4-shell`

---

## The 30-second context

Syncra is a Flutter AI career copilot. Stack: **Flutter + Firebase + Anthropic
Claude + JSearch + Gmail API**. No backend server. Demo target: June 16, 2026.

You own **everything that isn't chat/agent surfaces**: sign-in, onboarding,
dashboard, profile/settings, and the Applications page. **The UI scaffolding
exists** — sign-in works, profile page is 765 lines with beautiful UI, the old
tracker page streams from Firestore. **Your job is the wiring** — most of
these screens don't actually persist what the user does.

You're also the team's "no" person on PRs that touch the provider tree
([app.dart](../../lib/app.dart)) or `pubspec.yaml`.

## What's already shipped in YOUR area

- **Sign-in** via Google ([lib/features/auth/services/google_auth_service.dart](../../lib/features/auth/services/google_auth_service.dart))
  — works end-to-end. Creates `users/{uid}` doc on first sign-in.
- **[lib/features/auth/state/auth_controller.dart](../../lib/features/auth/state/auth_controller.dart)** —
  manages `_appUser` state, calls `UserRepository.ensureUserDoc` after sign-in.
- **[lib/features/auth/presentation/onboarding_page.dart](../../lib/features/auth/presentation/onboarding_page.dart)** —
  shows a prompt about extracting skills and capturing role… but the button
  **just navigates to dashboard, captures nothing**.
- **[lib/features/dashboard/presentation/dashboard_page.dart](../../lib/features/dashboard/presentation/dashboard_page.dart)** —
  has prompt-preview cards that deep-link into the chat. Doesn't have a
  top-level prompt input yet.
- **[lib/features/profile/presentation/profile_page.dart](../../lib/features/profile/presentation/profile_page.dart)** —
  765 lines of beautiful UI: autonomy three-position selector, settings tiles,
  card layouts. **Writes to nothing.** Pure UI today.
- **[lib/features/applications/](../../lib/features/applications/)** (was tracker) —
  page streams from `users/{uid}/applications/`, shows status filter chips,
  detail bottom sheet. Currently uses the multi-stage status enum that the
  brainstorm killed.
- **[lib/data/firestore/user_repository.dart](../../lib/data/firestore/user_repository.dart)** —
  has `ensureUserDoc(firebaseUser)` + `watchUser(uid)`. **Missing `update(...)`** — you add it.
- Router: [lib/core/router/app_router.dart](../../lib/core/router/app_router.dart) — works.
- Design system: [lib/shared/widgets/](../../lib/shared/widgets/) — already there.

## What you need to build

In priority order.

### 1. Add `UserRepository.update()` method (~1h, blocks everything else)

In [user_repository.dart](../../lib/data/firestore/user_repository.dart) add:

```dart
Future<void> update(String uid, Map<String, dynamic> patch) {
  return _paths.user(uid).update(patch);
}
```

Use this for any settings/onboarding writes. Pass partial maps like
`{'autonomy_level': 'ask_first'}` — Firestore merges them in.

### 2. Onboarding captures and persists user data (~3h)

[onboarding_page.dart](../../lib/features/auth/presentation/onboarding_page.dart)
currently just navigates. Make it real:

- Add a text field: *"What role are you aiming for?"* (e.g. "Senior UX Designer").
- Add a three-option picker for `autonomy_level`:
  - **suggest** — "Show me ideas, I'll act"
  - **ask_first** — "Run things by me before acting"
  - **auto_apply** — "Apply on my behalf when you're confident"
- On submit: call `userRepository.update(uid, {'role': ..., 'autonomy_level': ...})`.
- Then navigate to dashboard.

The brief reasoner ([passive_agent_controller.dart](../../lib/features/agent/state/passive_agent_controller.dart))
already reads `role` — so onboarding feeds it.

### 3. Dashboard prompt input → chat (~2h)

The dashboard has prompt-preview cards already, but no top-level prompt input
("Perplexity-style"). Add one:

- Top of dashboard: a large `TextField` with placeholder *"What would you
  like the agent to do today?"*
- On submit: navigate to chat (`context.go(RouteNames.agentChat)`) with the
  prompt prefilled and auto-submitted. The existing dashboard prompt-preview
  cards already do something similar via `AgentChatController.sendPrompt(...)`
  — copy that pattern.

### 4. Wire profile settings UI to Firestore (~3-4h)

[profile_page.dart](../../lib/features/profile/presentation/profile_page.dart)
has all the UI built but no persistence. For each interactive element:

- **Autonomy selector** (line ~244-260) — on selection, call
  `userRepository.update(uid, {'autonomy_level': selectedValue})`.
- **Sign out** — call `authController.signOut()`. Router auto-redirects to
  login.
- **Delete account** — confirmation dialog → call a new
  `userRepository.deleteUserData(uid)` method (cascade-deletes all
  subcollections + the user doc, then `authController.signOut()`).

Read the current state via `UserRepository.watchUser(uid)` so the UI reflects
Firestore.

### 5. Activity-log refactor of Applications page (~4-5h, biggest task)

The Applications page (was tracker) currently uses the multi-stage status
enum (submitted/viewed/replied/interview/offer/rejected). We're dropping that
because we can't observe inbox events — those statuses would stay stuck at
"submitted" forever.

**New schema** per [api-contract.md §3](../api-contract.md):

| Field | Type |
|---|---|
| `job` | map |
| `resume_id` | string |
| `drafted_at` | Timestamp |
| `sent_at` | Timestamp? (null = still drafting) |
| `got_reply` | bool (user-flippable toggle) |
| `follow_up_at` | Timestamp? |
| `notes` | array<{body, created_at}> |
| `sent_email_id` | string? (Gmail message id, set by Role 2's send_email) |

**Implementation:**

a. Update
   [lib/data/firestore/applications_repository.dart](../../lib/data/firestore/applications_repository.dart) —
   change the read mapping to the new shape. Add helper methods:
   - `setReply(uid, appId, gotReply)` — toggle
   - `setFollowUp(uid, appId, when)` — set follow-up date
   - `markSent(uid, appId, sentEmailId)` — called when Role 2's `send_email`
     succeeds (you may need to coordinate so the tool handler writes this).

b. Rebuild
   [lib/features/applications/presentation/applications_page.dart](../../lib/features/applications/presentation/applications_page.dart) —
   - Sort by date (most recent drafted/sent first).
   - Each card shows: company + role, "drafted Mon 9am" or "sent Tue 4pm",
     resume version used (tap to view), notes count, follow-up date (if set).
   - On each card: a `Switch` for "Got a reply" → calls
     `repository.setReply(...)`.
   - Filter chips: `All / Drafts / Sent / Replied`.

c. Update the existing detail sheet
   ([application_detail_sheet.dart](../../lib/features/applications/presentation/widgets/application_detail_sheet.dart)) —
   replace status picker with: "Got a reply" switch + follow-up date picker +
   notes (keep the existing notes input).

d. Update
   [lib/features/applications/state/applications_controller.dart](../../lib/features/applications/state/applications_controller.dart) —
   drop the status enum APIs, add `toggleReply(appId, value)`,
   `setFollowUp(appId, when)`.

### 6. Empty states everywhere (~2h)

For each list-based screen, design a beautiful empty state:

- **No resume uploaded** (on resume list, on tailor page if no source resume)
- **No jobs in pipeline** (on jobs page)
- **No applications yet** (on applications page)
- **No notifications** (coordinate with Role 5 — they own the page)

Each empty state: icon + headline + 1-line explanation + ONE-tap CTA (e.g.
"Open chat", "Upload resume", "Generate brief").

### 7. README setup section (~1h)

Currently the README has no `--dart-define` instructions. Add a section:

```markdown
## Running locally

Required `--dart-define` flags:

| Flag | What it is | Where to get it |
|---|---|---|
| ANTHROPIC_API_KEY | Claude API key | https://console.anthropic.com → API Keys |
| RAPIDAPI_KEY | JSearch via RapidAPI | https://rapidapi.com/.../jsearch |
| HUNTER_API_KEY | (optional) Hunter.io | https://hunter.io |

Recipe:

\```bash
flutter run \
  --dart-define=ANTHROPIC_API_KEY=sk-ant-... \
  --dart-define=RAPIDAPI_KEY=... \
  --dart-define=HUNTER_API_KEY=...
\```
```

Save your friends 30 minutes each.

### 8. Polish loop (ongoing)

Animations, snackbar consistency, error styling. Last 2 weeks.

## Files you own

```
lib/main.dart                                ← rarely touched
lib/app.dart                                 ← provider tree (touch carefully — coordinate w/ Role 3)
lib/core/                                    ← router, theme, constants
lib/features/auth/                           ← sign-in, onboarding
lib/features/dashboard/                      ← landing screen + prompt input
lib/features/profile/                        ← settings page
lib/features/applications/                   ← activity-log Applications page
lib/data/firestore/user_repository.dart      ← add update() method
lib/shared/widgets/                          ← design system
README.md                                    ← setup section
firestore.rules                              ← deployed, don't change without team vote
```

## You're done when

- A brand new user can sign in → onboard (captures role + autonomy) → land on
  dashboard with a working prompt input → tap chat → see the agent ask a
  sensible question.
- Profile settings persist: autonomy change reflects in Firestore + survives
  app restart. Sign out works on iOS/Android/web. Delete account cascades.
- Applications page shows a date-sorted activity log, no fake auto-statuses.
  "Got a reply" switch persists. Follow-up date picker works.
- Every list view has a beautiful empty state with a one-tap CTA.
- README has a working "how to run this app" section.

## Coordination handshakes — week 1

| Handshake | With | Lock in week 1 |
|---|---|---|
| Add `gmail.send` OAuth scope | Role 2 | Update GoogleSignIn config — they test it boots |
| Provider tree changes | Role 3 | Coordinate any changes to [app.dart](../../lib/app.dart) so chat controller still wires correctly |

## Common pitfalls

- **Don't restructure the provider tree.** AgentChatController has subtle
  dependencies — coordinate any changes with Role 3.
- **Don't break the `go_router` redirect logic** — it handles auth gating.
- **Don't add a new top-level dependency without team vote.** Lockfile rule:
  if you touch pubspec.yaml, you regenerate pubspec.lock.
- **Don't fork the design-system widgets** — extend the ones in `lib/shared/widgets/`.
- **Test sign-out + sign-in cycle on iOS** — it's the platform where the
  Google Sign-In SDK is most opinionated.

## Relevant contract sections

- [api-contract.md §3 Firestore data model](../api-contract.md) — especially
  `users/{uid}` and the new applications schema
- [api-contract.md §5.3 Gmail API](../api-contract.md) — OAuth scope details
  (you coordinate with Role 2 on this)

## How to use this brief with your AI

Paste this entire file as your first message to Claude / ChatGPT / Copilot.
Then ask:

> *"Read this brief. I'm Role 4. The Applications page activity-log refactor
> is the biggest unknown for me — walk me through the schema change before I
> touch any Flutter code."*

The AI will help you sequence: data model first, repository methods second,
UI rebuild third. That's the right order.
