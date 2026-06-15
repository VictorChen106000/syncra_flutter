# Syncra

**An AI career agent inside a Flutter app.** You tell it what you want — *"get me
a UX role at an AI startup, ready to send by tonight"* — and it searches jobs,
matches them to your resume, proposes targeted resume edits, drafts the outreach
email, and lines it up for one tap to send. You review and approve at every step.

**Demo day:** June 16, 2026 · **Stack:** Flutter + Firebase + Claude · **Firebase-only backend.**

## Docs

Three files, split by how often they change:

| File | What | Changes |
| --- | --- | --- |
| **README.md** (this) | What Syncra is, the demo, the stack | rarely |
| **[ARCHITECTURE.md](./ARCHITECTURE.md)** | How it's wired — data model, tools, agent loop, state, APIs | by PR |
| **[STATUS.md](./STATUS.md)** | What's done, what's left, who owns it | daily |

If you're picking up work, read all three in that order, then check STATUS.md.

## The problem

Job hunting is 90% boring orchestration: scroll listings, paste keywords into
your resume, rewrite the same email, hunt for a hiring manager, send, repeat.
Existing tools each handle one slice — LinkedIn for search, Resumeworded for
keywords, ChatGPT for drafting, Notion for tracking — and the user is the duct
tape between them. **Syncra is the duct tape, automated.**

## The 60-second demo

1. Sign in with Google.
2. Upload your resume (PDF) — stored in Firebase Storage.
3. Open chat. Type: *"Help me apply to a senior UX role at an AI startup, remote."*
4. Agent searches jobs → ranks them qualitatively → asks *"Linear is the top
   match. Tailor for them?"* → you tap **Yes**.
5. Agent reads your resume → proposes 3–8 targeted edits. You see a PR-style
   change log with the original text, rewrite, and one-line reason.
6. Syncra renders an unsaved tailored PDF preview. You inspect the changes,
   then save the tailored resume or dismiss it.
7. Agent runs Trust Guard for obvious job red flags, resolves the best available
   recipient, then drafts a cold-outreach email if the role looks normal or you
   approve continuing.
8. You review the email and save it to Gmail Drafts on web or mobile. If using
   send mode, a separate explicit tap is still required before anything is
   delivered.

End to end in ~2 minutes, with the user reviewing — never blindly trusting — at
two explicit gates: the diff viewer and the email modal.

## Demo runbook

Use this before a live demo or team smoke test.

### Required keys

Run the app with compile-time keys. Do not commit real keys.

```powershell
flutter run -d chrome `
  --dart-define=ANTHROPIC_API_KEY=sk-ant-... `
  --dart-define=RAPIDAPI_KEY=...
```

For Android emulator:

```powershell
flutter run -d emulator `
  --dart-define=ANTHROPIC_API_KEY=sk-ant-... `
  --dart-define=RAPIDAPI_KEY=...
```

The debug-only Profile → Developer panel shows whether both keys are present. It
does not reveal the key values.

### Web storage check

If demoing on Chrome, Firebase Storage CORS must allow the web origin. Without
CORS, resume upload can succeed but later PDF download / parsing can fail in the
browser. If demoing on Android or iOS, this browser CORS step can be skipped.

Create a temporary `cors.json` file outside the repo:

```json
[
  {
    "origin": ["http://localhost:*", "https://localhost:*"],
    "method": ["GET", "HEAD", "PUT", "POST", "DELETE"],
    "responseHeader": ["Content-Type", "Authorization", "x-goog-resumable"],
    "maxAgeSeconds": 3600
  }
]
```

Then apply it to the Firebase Storage bucket:

```powershell
gsutil cors set cors.json gs://YOUR_FIREBASE_STORAGE_BUCKET
```

Verify it:

```powershell
gsutil cors get gs://YOUR_FIREBASE_STORAGE_BUCKET
```

After CORS is set, smoke-test this exact Chrome path: upload a text-based resume
PDF, open preview, ask Syncra to tailor it, and confirm the generated PDF preview
loads without `ClientException: Failed to fetch`.

### Build commands

Android release APK:

```powershell
flutter build apk --release `
  --dart-define=ANTHROPIC_API_KEY=sk-ant-... `
  --dart-define=RAPIDAPI_KEY=...
```

Web release build:

```powershell
flutter build web --release `
  --dart-define=ANTHROPIC_API_KEY=sk-ant-... `
  --dart-define=RAPIDAPI_KEY=...
```

### Feature freeze and bug bash

About one week before the demo, stop adding new product features. From that
point on, only make changes that improve demo reliability:

- Fix crashes, compile errors, failed tests, and broken navigation.
- Fix demo-path bugs in resume upload, job search, Trust Guard, tailoring,
  email review, Applications, and Profile settings.
- Improve unclear error messages only when they unblock the demo.
- Do not add new screens, new agent tools, new Firebase collections, or new
  flows unless the whole team agrees it is required for the demo.
- Run `flutter test` and `flutter analyze` after every bug-bash change.

### One-hour team smoke test

Each teammate should run through:

1. Sign in with Google or email/password.
2. Upload a text-based resume PDF.
3. Ask Syncra to find matching jobs.
4. Open a role, run Trust Guard, and save it.
5. Tailor a resume and preview the generated PDF.
6. Draft outreach, save a Gmail draft, and confirm no email is sent without a tap.
7. Check Applications for quality, bundle, trust, and bounded auto-apply status.
8. Reset account only after confirming the demo path works.

### Post-demo shutdown

After the live demo:

1. Rotate the Anthropic API key used for `ANTHROPIC_API_KEY`.
2. Rotate the RapidAPI key used for `RAPIDAPI_KEY`.
3. Remove old keys from local terminal history, screenshots, notes, and team chat.
4. Check provider usage dashboards and confirm spend caps were not exceeded.
5. Delete the temporary `cors.json` file if it was created outside the repo.
6. Rebuild only with the new keys if the team needs another demo build.

## What makes Syncra different

- **One agent, two triggers — both user-initiated.** One Claude agent, one tool
  registry. The user invokes it by typing a chat prompt, or by tapping *"Run
  today's brief"* on the dashboard (a canned prompt, same code path). Nothing
  fires on app open.
- **Tailoring is a reviewable change log, not a rewrite.** The agent proposes
  targeted edits with reasons, renders a tailored PDF preview, and shows what
  changed before you save anything. Your original resume is never touched.
- **The agent learns about you.** When you answer a follow-up question, the
  agent persists it as a learned fact, so it doesn't ask twice.
- **Trust Guard before outreach.** Before saving or drafting for a role, Syncra
  checks for obvious scam signals and shows the result on pipeline and
  application cards. It never claims a job is guaranteed safe.
- **Recipient Intelligence, not fake recruiter lookup.** JSearch does not
  provide recruiter emails. Syncra prefers confirmed `company_contacts` and a
  future Firebase-only official-site discovery hook, but `careers@domain` is
  labeled as a low-confidence guess. Syncra never guarantees an inbox is valid,
  never scrapes LinkedIn/social/private profile pages, and never auto-sends to
  guessed recipients.
- **Walk-away support.** Leave the chat mid-task and agent updates land in the
  in-app notifications inbox — answer or approve from there.
- **Persistent chat workspace.** Conversations are saved as versioned Firestore
  snapshots and reopen from a polished drawer with date grouping, preview text,
  local title/search, rename, pin/unpin, and delete confirmation. Reopen restores
  user bubbles, selected resume attachments, tool rows, job cards, dismissed /
  hidden / already-handled job results, proposal cards, resume preview cards,
  email draft cards, job-thread context, and compact model-side context so the
  next message can continue naturally.
- **Human-in-the-loop.** The agent never sends external traffic without an
  explicit user tap. Missing context → it pauses and asks.
- **Honest scope.** The Applications page is an activity log (drafted / sent /
  user-flipped "got reply"), not a fake multi-stage CRM.
- **Free to run.** Firebase Spark plan, no server. The only cost is Claude
  tokens, capped at ~$5/month.

## Stack

- **Flutter** (iOS / Android / Web) — entire app, including the agent loop and tool registry
- **Firebase Auth** (Google Sign-In + email/password) · **Cloud Firestore** (Spark) · **Firebase Storage** (resume files)
- **Anthropic Claude** (Haiku 4.5) — agent brain, called directly from Flutter
- **JSearch / RapidAPI** — live job listings, not recruiter email data
- **Gmail API** — save Gmail drafts with `gmail.compose` and send confirmed emails
  with `gmail.send`; never Gmail read scope

No Railway, FastAPI, Render, Heroku, or custom Python backend is used. v1 keeps
external API calls in Flutter for the final demo; Firebase Cloud Functions is a
future Firebase-only backend extension, not part of this build.

## Out of scope for v1

Push notifications (FCM), auto-submit, cover-letter documents, LinkedIn
integration/scraping, multi-account Gmail, calendar / interview scheduling.
