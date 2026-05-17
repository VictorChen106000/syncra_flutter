# Per-role briefs — Syncra demo (June 16, 2026)

Each `.md` file in this folder is a **self-contained brief for one person**. Pick
your role, open the file, paste the whole thing as the first message to your
AI assistant (Claude Code, ChatGPT, Copilot Chat, whatever), then ask:

> *"Read this brief. What should I start with?"*

The brief tells the AI:
- What the app is and what's already shipped
- Your role's scope and what's already built in your area
- What you need to build (numbered, with file paths)
- Acceptance criteria
- Coordination handshakes with other roles
- Common pitfalls

## The 5 roles

| File | Role | Owner | Hours |
|---|---|---|---|
| [01-resume-pipeline.md](./01-resume-pipeline.md) | Backend — Resume Pipeline | Friend 1 | ~6-8h + demo prep |
| [02-api-fetch.md](./02-api-fetch.md) | Backend — API Fetch (JSearch + Gmail) | Friend 2 | ~14-18h |
| [03-agent-reasoning.md](./03-agent-reasoning.md) | Backend — Agent Reasoning | **You** (team lead) | ~11-14h |
| [04-shell-onboarding.md](./04-shell-onboarding.md) | Frontend — Shell, Onboarding, Applications page | Friend 3 | ~14-17h |
| [05-surfaces-notifications.md](./05-surfaces-notifications.md) | Frontend — Chat surfaces, Email modal, Notifications inbox | Friend 4 | ~14-18h |

## Before you start — read these in order

1. [product-brief.md](../product-brief.md) — what Syncra is (~3 min)
2. [api-contract.md](../api-contract.md) — the technical spec (~10 min skim)
3. Your role file in this folder

## The three critical handshakes (week 1)

Roles depend on each other. Lock these in week 1 or you'll deadlock late:

| Handshake | Between | Decide |
|---|---|---|
| OAuth scope | Role 2 ↔ Role 4 | Add `gmail.send` to Google Sign-In config |
| Send-email confirmation token | Role 2 ↔ Role 5 | Token shape passed from review modal → `send_email` tool |
| Agent event stream | Role 3 ↔ Role 5 | `Stream<AgentEvent>` exposed at provider level for notifications inbox |
