# Syncra — Product Brief

**Status:** v1.3 — adds PR-diff resume tailoring + opt-in morning brief
**Audience:** team of 5, TA, anyone who needs the gist in 90 seconds
**Last updated:** 2026-05-17

---

## One-liner

**Syncra is an AI career agent inside your phone.** You tell it what you want
("get me a UX role at an AI startup, ready to send by tonight"), and it
searches, matches, tailors your resume, drafts the email, and lines everything
up for one tap to send. You stay in control — review, edit, or hand off — at
every step.

---

## The user problem

Job hunting is 90% boring orchestration: scroll listings, copy/paste keywords
into your resume, re-write the same cover letter, hunt for a hiring manager
on LinkedIn, draft the email, send, repeat. It's hours of low-leverage work
per application.

Existing tools each handle one slice — LinkedIn for search, Resumeworded for
keywords, ChatGPT for drafting, Notion for tracking. The user is the duct
tape between them. **Syncra is the duct tape, automated.**

---

## The 60-second demo path

1. **Sign in** with Google.
2. **Upload your resume** — one PDF, lives on the phone (no cloud cost).
3. **Tap the chat icon.** Type: *"Help me apply to a senior UX role at an AI startup, anywhere remote."*
4. Agent thinks → searches jobs → ranks them → asks: *"Linear is the top match (94%). Tailor for them?"* You tap **Yes**.
5. Agent reads your resume → **proposes 4–6 targeted edits.** You see them as a PR-style diff: original on top, rewrite below, one-sentence reason. Accept the ones you like, reject the rest.
6. Tap **Apply N edits.** A new tailored PDF renders from the accepted subset.
7. Agent drafts a cold-outreach email to Linear's head of design.
8. Screen shows: tailored resume preview + email draft + send button.
9. You tap **Send**. Email goes out via your own Gmail. Application appears on the **Applications** page.

End-to-end in ~2 minutes, with the user reviewing — never blindly trusting — the agent's output at two explicit gates (the diff viewer and the email modal).

---

## What makes Syncra different

**One agent, two triggers — both user-initiated.**

There is *one* Claude agent with one tool registry. The user invokes it two ways:

- **Chat trigger** — user types a prompt → chat opens → agent runs. Intentional, specific.
- **Brief trigger** — user taps *"Run today's brief"* on the dashboard. The
  agent fires a canned prompt (*"Find 5 fresh jobs matching my profile, score
  them, save them as pipeline cards"*). Same code path, same tools — the user
  just didn't have to type.

Both runs surface the same way: tool calls visible in the notifications inbox,
results landing on the pipeline page and/or in chat. **Nothing fires on app
open** — earlier drafts auto-ran the brief every 24h, which burned Claude
tokens on every launch. The brief is now opt-in (off by default; toggle in
Settings) and always requires a tap.

**Walk-away support.** Long-running agent work (tailoring, sending) doesn't
trap the user inside the chat. The in-app **notifications inbox** receives
agent updates — accept / edit / answer follow-up questions from there without
re-entering the chat. The agent loop continues in the background; results
land in notifications.

**The agent learns about you.** When the user answers an `ask_user` question
("yes, I did lead A/B tests at Acme"), the agent persists that as a learned
fact. Next time tailoring for a role that mentions A/B testing, the agent uses
the fact without asking again. The resume effectively grows smarter with use.

**Honest about scope.** The Applications page is an activity log, not a CRM.
It shows what the agent drafted/sent, with timestamps and the resume version
used. The user can manually toggle "got a reply" and add notes. We don't
pretend to read the user's inbox, so we don't fake multi-stage status updates.

**Human-in-the-loop, by design.**
- The agent never auto-sends without a user tap (in v1).
- When it's missing context ("what's your salary floor?"), it pauses and
  shows a text field. The user types, the agent resumes. No silent guessing.
- The user's autonomy level (`suggest` / `ask_first` / `auto_apply`) is
  stored in their profile — easy to crank up later without rewriting the loop.

**Tailoring is a pull request, not a rewrite.** When the agent tailors your
resume, it doesn't hand you a finished PDF and hope you like it. It proposes
a short list of targeted edits — *"replace this bullet with this; reason:
matches the JD's growth-metrics emphasis"* — and you accept or reject each one
like reviewing a GitHub PR. Only after you tap **Apply N edits** does a new
tailored PDF get rendered. Your original resume is never touched.

**Single PDF template.** Tailored resumes render into the same clean, ATS-safe
layout as your original. The agent only paraphrases text — never invents
experience, never touches design.

**100% free to run.** Spark plan, no credit card, no servers. The only thing
that costs money is Claude tokens, capped at ~$5/month for our usage.

---

## Tech stack at a glance

```
                    ┌─────────────────────────────────┐
                    │       FLUTTER APP (client)      │
                    │   - UI                          │
                    │   - Agent loop + tool registry  │
                    │   - PDF render (pdf package)    │
                    └────────────┬────────────────────┘
                                 │
       ┌───────────┬─────────────┼──────────────┬──────────────┐
       ▼           ▼             ▼              ▼              ▼
  Firebase Auth  Firestore   Anthropic       JSearch       Gmail API
  (Google      (users,       Claude         (RapidAPI)    (send emails,
   Sign-In)    apps, jobs)   (Haiku 4.5)                  user's account)
                                                                ▲
                                                                │
                                                        Hunter.io (optional)
                                                        Find hiring-mgr emails
```

**No self-hosted server. No Cloud Functions. No Firebase Storage.**
Everything is client logic + free Firebase services + a handful of third-party APIs.

---

## What ships for the demo

| Feature | In v1 demo |
|---|---|
| Google sign-in | ✅ |
| Resume upload (Firebase Storage) | ✅ |
| Agent chat with tool use | ✅ |
| Job search (JSearch + Firestore cache) | ✅ |
| Job matching & ranking | ✅ |
| Resume parsing (lazy, on first tailor) | ✅ |
| Resume tailoring + PDF render | ✅ |
| Email drafting | ✅ |
| Email sending via Gmail API | ✅ |
| Hiring-manager lookup (Hunter.io) | 🤔 Stretch |
| Activity-log Applications page (drafted/sent + user-flipped "got reply") | 🟡 simplify schema |
| Agent learns across sessions via `remember_fact` (persistent learned facts) | ⏳ B3 task |
| In-app notification inbox for async agent updates (walk-away support) | 🟡 wiring |
| `ask_user` text-field mid-flow | ✅ |

**Out of scope for v1:** *push* notifications (FCM), cross-device sync, scheduled
agent runs, auto-submit, cover-letter generation as a separate document,
LinkedIn integration, real-time job-source webhooks.

---

## The narrative for demo day

> "Most career tools are a dashboard of features. We built an agent.
>
> Watch — I type one sentence: *'help me apply to a UX role at an AI startup.'*
> No filters, no keywords, no forms. The agent reads my resume, searches
> live job boards, picks the best fit, and proposes a handful of targeted
> rewrites — I accept the ones I like, like reviewing a pull request. Then
> it drafts the email to the hiring manager. I read it, hit send. Done.
>
> The whole thing runs on Flutter, Firebase, and Claude. No backend
> server. Free to operate. We can demo on any phone right now."

That's the pitch. Two sentences of code-architecture commentary, then a live demo.

---

## Status

- **Tech stack migrated** to Flutter + Firebase + Claude (May 2026).
- **Architecture contract** in [api-contract.md](./api-contract.md).
- **Team plan** in [team-handoff.md](./team-handoff.md) (per-track) + [roles/](./roles/) (per-person).
- **Demo target:** June 16, 2026.
