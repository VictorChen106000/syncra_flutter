# Role 5 — Integrations & Send (I, Backend + Modal UI)

**Track:** I — Integrations & Send (JSearch + Gmail + email review modal)
**Estimated hours:** ~16–18h
**Demo day:** 2026-06-16

---

## The 30-second context

Syncra is a Flutter + Firebase career-agent app. You wire the **outside
world**: real job listings (JSearch), real email send (Gmail API from the
user's own account), and the send-gate UI (email review modal) that pairs
naturally with the send tool.

Without your work, the agent is a polished demo of fake data. Tap *"send"*
and nothing leaves the device. JSearch + Gmail are what make Syncra a real
product, not a UI walkthrough.

Stack: Flutter, `googleapis` + `googleapis_auth`, direct HTTP to RapidAPI.

---

## What's already shipped in YOUR area

| Piece | Status |
|---|---|
| `search_jobs` tool — reads pre-seeded jobs/ collection (~10 stale entries) | 🟡 — replace data source |
| `send_email` tool — exists but doesn't actually send | 🟡 — wire to Gmail |
| Google Sign-In via Firebase Auth | ✅ — but missing `gmail.send` scope |
| JSearch logic in old Python backend (`backend/app/jobs/sources.py`) | ✅ — port to Dart |
| `email_review_page.dart` | ❌ — create |
| `gmail_service.dart` | ❌ — create |
| `jsearch_service.dart` | ❌ — create |

---

## What you need to build

### 1. JSearchService (~3h)
Create `lib/data/services/jsearch_service.dart`. Direct HTTP to RapidAPI.
Port the logic from the old Python `sources.py` — it's already proven
against the JSearch schema; you're just translating Python → Dart.

```dart
class JSearchService {
  Future<List<Job>> search({
    required String query,
    String? location,
    int limit = 10,
  });
}
```

Headers: `x-rapidapi-key`, `x-rapidapi-host: jsearch.p.rapidapi.com`.
Key from `--dart-define=RAPIDAPI_KEY=...`. Free tier: 200 req/month.

Upsert results into Firestore `jobs/` with the deterministic ID scheme from
the old Python code (`_jobIdFor()` hash). **Trim descriptions to ~240 chars**
before storing — JSearch returns 10KB+ per result.

### 2. In-memory cache (~30 min)
Map `(query, location) → results` keyed for **1 hour**. Stays under the
200/month quota during dev + demo.

### 3. Replace `search_jobs` executor (~1h)
In [lib/features/agent_chat/tools/builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart),
the `search_jobs` executor currently does `repo.fetchAll(40)`. Replace with
`jsearchService.search(query, location, limit)`. **Keep the return shape
identical** (same `Job` model) so Claude's downstream tool calls don't change.

### 4. Gmail OAuth scope (~30 min)
Coordinate with **F (App Shell)** to add
`https://www.googleapis.com/auth/gmail.send` to the existing GoogleSignIn
config. Gmail's `gmail.send` scope triggers an unverified-app warning at
sign-in — that's fine for a class demo. **Tell the TA in advance** so they
aren't surprised.

### 5. GmailService (~3h)
Create [lib/features/email/services/gmail_service.dart](../../lib/features/email/services/gmail_service.dart).
Add `googleapis` + `googleapis_auth` to [pubspec.yaml](../../pubspec.yaml).

```dart
class GmailService {
  Future<String> send({
    required String to,
    required String subject,
    required String body,
    List<String> pdfAttachmentPaths = const [],
  }); // returns Gmail message_id
}
```

Build a base64-encoded MIME message with optional `application/pdf` parts.
Post to `users.messages.send`. Auth via the existing Google Sign-In
credential (now scoped for `gmail.send`).

### 6. Replace `send_email` executor (~2h)
The tool **must refuse to send** unless the call carries an explicit
`confirmed: true` flag (or a one-shot confirmation token). The only path that
sets it is the email review modal (next item).

After successful send, write `sent_at` and `sent_email_id` (Gmail message id)
to the application doc per [api-contract.md §3](../api-contract.md).

### 7. Email review modal (~3h)
Create [lib/features/email/presentation/email_review_page.dart](../../lib/features/email/presentation/email_review_page.dart).
Modal sheet with:

- Editable subject + body (pre-filled from `draft_email` output)
- Recipient display ("Send to {recipient_email}")
- **Send** button (the only path to actually fire `send_email`)
- Cancel button (closes modal, dispatches nothing)

On Send tap: generate a one-shot UUID, pass it to `send_email` as a
confirmation token, validate it in your executor. Coordinate with A on how
the modal calls the chat controller to dispatch the tool.

### 8. (Stretch) HunterService (~2h)
Create `lib/data/services/hunter_service.dart`. Single endpoint
(`https://api.hunter.io/v2/domain-search`). Free tier: 25 searches/month —
cache by company for 24h.

### 9. (Stretch) `lookup_hiring_manager` tool
Wire HunterService into the executor in `builtin_tools.dart`. If the stretch
is cut, the `draft_email` flow falls back to `careers@{company}.com` guess —
make sure that fallback exists either way.

---

## Files you own

- `lib/data/services/jsearch_service.dart` (NEW)
- `lib/data/services/hunter_service.dart` (NEW, stretch)
- `lib/features/email/services/gmail_service.dart` (NEW)
- `lib/features/email/presentation/email_review_page.dart` (NEW)
- `search_jobs`, `send_email`, `lookup_hiring_manager` executors in [builtin_tools.dart](../../lib/features/agent_chat/tools/builtin_tools.dart)
- Confirmation-token contract with A's chat controller

**You do NOT touch:**
- Resume features — R1 / R2 own
- `tailor_resume` / `apply_resume_edits` executors — R1 owns
- Agent loop / system prompt / `ask_user` — A owns
- App shell / settings / GoogleSignIn config file — F owns (but you coordinate with them for the scope addition)
- `draft_email` prompt — A owns (you only consume its output in the modal)

---

## You're done when

- Typing *"find UX designer jobs in Singapore"* in chat returns real, current Singapore listings (not the seeded data).
- The email review modal exists and is the **only** path to actually sending email. Tapping Send delivers a real email to the recipient's inbox, with the tailored PDF attached, from the user's own Gmail.
- `send_email` refuses to send without the confirmation token.
- `applications/{appId}.sent_at` and `sent_email_id` are written on successful send.
- (Stretch) `lookup_hiring_manager` returns a real name+email for known company domains; falls back to `careers@{company}.com` otherwise.

---

## Coordination handshakes — week 1

| Day | With | Decide |
|---|---|---|
| Day 1 | F | Gmail OAuth scope (`gmail.send`) addition to GoogleSignIn config |
| Day 2 | A | Confirmation-token shape — UUID generated by modal, validated by `send_email` executor |
| Day 2 | A | Chat controller method the modal calls to dispatch `send_email` |
| Day 3 | R2 | When `draft_email` tool result lands, R2's chat block triggers your modal — agree on navigation handoff |

---

## Common pitfalls

- **Don't cache JSearch by raw URL.** Use the deterministic `_jobIdFor()` hash from the old Python — JSearch sometimes returns the same job with two different `job_apply_link` values.
- **Don't store full 10KB descriptions.** Trim to 240 chars before Firestore write.
- **Never log API keys.**
- **Don't bypass the review modal** for `send_email` — the whole point is "the user explicitly tapped Send."
- **Gmail unverified-app warning is expected.** Tell the TA. Don't try to get the app verified before the demo (it's a multi-week process).
- **Don't add `gmail.readonly` scope** without a team vote — `gmail.send` only per [api-contract.md §11.5](../api-contract.md).

---

## Relevant contract sections

- [api-contract.md §2.1](../api-contract.md) — `search_jobs`
- [api-contract.md §2.5](../api-contract.md) — `draft_email` (you consume its output)
- [api-contract.md §2.6](../api-contract.md) — `lookup_hiring_manager` (stretch)
- [api-contract.md §2.8](../api-contract.md) — `send_email` (human-in-the-loop, confirmation required)
- [api-contract.md §3 applications](../api-contract.md) — `sent_at`, `sent_email_id` fields you write
- [api-contract.md §5](../api-contract.md) — external API config (Anthropic, JSearch, Gmail, Hunter)
- [api-contract.md §8](../api-contract.md) — rate limits

---

## How to use this brief with your AI

Paste this whole file as your first message to Claude / ChatGPT / Copilot,
then ask:

> *"Read this brief. What should I start with?"*

The AI should suggest: JSearch first (no external blockers — port the Python
code), then coordinate the Gmail scope with F on day 1, then GmailService +
modal in parallel. Hunter last; it's stretch.
