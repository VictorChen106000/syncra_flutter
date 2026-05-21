# Syncra

**An AI career agent inside a Flutter app.** You tell it what you want — *"get me
a UX role at an AI startup, ready to send by tonight"* — and it searches jobs,
matches them to your resume, proposes targeted resume edits, drafts the outreach
email, and lines it up for one tap to send. You review and approve at every step.

**Demo day:** June 16, 2026 · **Stack:** Flutter + Firebase + Claude · **No backend server.**

## Docs

Three files, split by how often they change:

| File | What | Changes |
|---|---|---|
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
4. Agent searches jobs → ranks them → asks *"Linear is the top match (94%).
   Tailor for them?"* → you tap **Yes**.
5. Agent reads your resume → proposes 3–8 targeted edits. You see each as a
   PR-style diff (original, rewrite, one-line reason) and accept or reject each.
6. Tap **Apply N edits** → a new tailored PDF renders from the accepted subset.
7. Agent drafts a cold-outreach email to the hiring manager.
8. You review, tap **Send** → email goes out via your own Gmail. The application
   appears on the Applications page.

End to end in ~2 minutes, with the user reviewing — never blindly trusting — at
two explicit gates: the diff viewer and the email modal.

## What makes Syncra different

- **One agent, two triggers — both user-initiated.** One Claude agent, one tool
  registry. The user invokes it by typing a chat prompt, or by tapping *"Run
  today's brief"* on the dashboard (a canned prompt, same code path). Nothing
  fires on app open.
- **Tailoring is a pull request, not a rewrite.** The agent proposes a short
  list of targeted edits with reasons; you accept or reject each like a GitHub
  PR. Only after **Apply N edits** does a tailored PDF render. Your original
  resume is never touched.
- **The agent learns about you.** When you answer a follow-up question, the
  agent persists it as a learned fact, so it doesn't ask twice.
- **Walk-away support.** Leave the chat mid-task and agent updates land in the
  in-app notifications inbox — answer or approve from there.
- **Human-in-the-loop.** The agent never sends external traffic without an
  explicit user tap. Missing context → it pauses and asks.
- **Honest scope.** The Applications page is an activity log (drafted / sent /
  user-flipped "got reply"), not a fake multi-stage CRM.
- **Free to run.** Firebase Spark plan, no server. The only cost is Claude
  tokens, capped at ~$5/month.

## Stack

- **Flutter** (iOS / Android / Web) — entire app, including the agent loop and tool registry
- **Firebase Auth** (Google Sign-In) · **Cloud Firestore** (Spark) · **Firebase Storage** (resume files)
- **Anthropic Claude** (Haiku 4.5) — agent brain, called directly from Flutter
- **JSearch / RapidAPI** — live job listings
- **Gmail API** — send drafted emails from the user's own account

No FastAPI, no Cloud Functions. Course rule: Flutter + Firebase only.

## Out of scope for v1

Push notifications (FCM), auto-submit, cover-letter documents, LinkedIn
integration, chat persistence (in-memory only), multi-account Gmail,
calendar / interview scheduling.
