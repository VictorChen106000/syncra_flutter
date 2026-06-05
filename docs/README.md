# Syncra

**An AI career agent inside a Flutter app.** You tell it what you want — *"get me
a UX role at an AI startup, ready to send by tonight"* — and it searches jobs,
matches them to your resume, proposes targeted resume edits, drafts the outreach
email, and lines it up for one tap to send. You review and approve at every step.

**Demo day:** June 16, 2026 · **Stack:** Flutter + Firebase + Claude · **No backend server.**

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
5. Agent reads your resume → proposes 3–8 targeted edits. You see each as a
   PR-style diff (original, rewrite, one-line reason) and accept or reject each.
6. Tap **Apply N edits** → a new tailored PDF renders from the accepted subset.
7. Agent runs Trust Guard for obvious job red flags, then drafts a cold-outreach
   email if the role looks normal or you approve continuing.
8. You review, tap **Send** → email goes out via your own Gmail. The application
   appears on the Applications page.

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

### One-hour team smoke test

Each teammate should run through:

1. Sign in with Google or email/password.
2. Upload a text-based resume PDF.
3. Ask Syncra to find matching jobs.
4. Open a role, run Trust Guard, and save it.
5. Tailor a resume and preview the generated PDF.
6. Draft outreach, review the email, and confirm no email is sent without a tap.
7. Check Applications for quality, bundle, trust, and bounded auto-apply status.
8. Reset account only after confirming the demo path works.

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
- **Walk-away support.** Leave the chat mid-task and agent updates land in the
  in-app notifications inbox — answer or approve from there.
- **Persistent chat history.** Conversations are saved and can be reopened from
  the chat history drawer instead of disappearing after one session.
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
- **JSearch / RapidAPI** — live job listings
- **Gmail API** — send drafted emails from the user's own account

No FastAPI, no Cloud Functions. Course rule: Flutter + Firebase only.

## Out of scope for v1

Push notifications (FCM), auto-submit, cover-letter documents, LinkedIn
integration, multi-account Gmail, calendar / interview scheduling.
