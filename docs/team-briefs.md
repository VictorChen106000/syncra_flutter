# Syncra Backend — Team Briefs

One paste-able prompt per person. Each person should paste **their section + the full
`docs/api-contract.md`** into their AI tool of choice as the system/initial prompt.

Demo target: **June 16, 2026**. Branch off `daryn/backend`. PRs back into `daryn/backend`.

---

## Shared rules (apply to everyone)

- Stack is locked: Python 3.12, FastAPI, Firestore, Firebase Auth, Anthropic SDK, uv, Railway.
  Don't introduce new frameworks (no SQLAlchemy, no Celery, no Redis, no Postgres).
- **Source of truth for shapes is `docs/api-contract.md`.** If your code disagrees with the
  contract, the contract wins. If the contract is wrong, fix the contract first, then code.
- **Stay in your folder.** Cross-folder edits = PR comment + revert. Shared types live in
  `app/schemas.py` (owned by C). If you need a new shared type, open a PR to `schemas.py`.
- **No mocking the LLM or Firestore in committed code.** Use real clients with cheap models
  for tests. If you stub locally, keep stubs out of commits.
- All async I/O. No blocking calls inside FastAPI route handlers.
- Field names: `snake_case`. Timestamps: ISO 8601 UTC strings. IDs: Firestore doc IDs.
- Every user-scoped query filters by `current_user.uid`. No exceptions.
- Long-running work (>2s) returns `202 + poll_url`. No SSE, no WebSockets, no background
  workers — just FastAPI `BackgroundTasks` writing status into Firestore.
- Rate limits live in `users/{uid}/usage/{YYYY-MM-DD}` — increment via Firestore transaction.
- Commit style: small, focused, conventional (`feat:`, `fix:`, `chore:`). Don't bundle.

---

## Person A — Resumes

**You own:** `backend/app/resumes/` (every file inside it).
**You DO NOT touch:** anything outside that folder. If you need a shared type or LLM
helper, ask C to add it.

**Endpoints to ship (see §3.3 of api-contract.md):**
- `GET /resumes`, `GET /resumes/tailored`, `GET /resumes/{id}`
- `POST /resumes/upload` (multipart, 5MB cap) — parses PDF/DOCX → `ResumeJSON`, stores both
- `DELETE /resumes/{id}`
- `POST /resumes/{id}/tailor` → 202 + poll URL
- `GET /resumes/tailoring/{tj_id}` — poll status

**Module responsibilities:**
- `router.py` — FastAPI routes only. Thin. Delegates to the modules below.
- `parser.py` — Extract text with `pypdf` / `python-docx`, then call Claude **Haiku** to map
  raw text → `ResumeJSON` (schema in contract §2). Return Pydantic model.
- `tailor.py` — Background task. Reads stored `ResumeJSON` + target Job, calls Claude
  **Opus** (or Sonnet — read `LLM_MODEL_STRONG` env), writes tailored `ResumeJSON`, kicks
  off `latex.render()`, uploads PDF via `storage.py`, writes new Resume doc with
  `source="tailored"`, `parent_resume_id`, `tailored_for_job_id`. Updates
  `tailoring_jobs/{tj_id}` status throughout (`pending` → `rendering` → `done` / `error`).
- `latex.py` — Render `ResumeJSON` → PDF by templating a `.tex` file (Jinja2) and shelling
  out to `tectonic`. Templates live in `app/resumes/templates/`. Start with ONE clean
  single-column template; don't over-engineer.
- `storage.py` — Firebase Cloud Storage uploads/downloads + signed URLs. Use
  `firebase.storage_bucket` from C's module.

**Dependencies from C (block until shipped):**
- `app/deps.py::current_user` — gives you `User` with `uid`
- `app/schemas.py` — `Resume`, `ResumeJSON`, `Job` Pydantic models
- `app/llm.py` — `llm.haiku(...)`, `llm.strong(...)` wrappers
- `app/firebase.py` — `db` (Firestore client), `storage_bucket`

**Day 1 (while waiting on C):** wire up `parser.py` with a hard-coded test PDF and the
Anthropic SDK directly; you'll swap to `llm.haiku()` when C ships it. Get the prompt
for PDF → ResumeJSON producing valid JSON reliably.

**Watch out for:**
- PDF parsing is messy. Validate `ResumeJSON` with Pydantic before storing — reject and
  return 422 if the LLM gives back garbage. Don't silently store broken data.
- Tectonic is slow on first run (downloads packages). Pre-warm the cache in the Dockerfile.
- 5MB upload cap — enforce in FastAPI, don't rely on Firebase.

---

## Person B — Jobs + Agent (THE HEART)

**You own:** `backend/app/jobs/` and `backend/app/agent/`.
**You DO NOT touch:** anything outside those two folders.

**Endpoints to ship (see §3.4 + §3.5 of api-contract.md):**
- `GET /jobs/{id}`, `POST /jobs/search`
- `POST /agent/brief` → 202 + poll URL (THE big one)
- `GET /agent/brief/{brief_id}` — poll with progress
- `GET /agent/pipeline` (filter by category, status, paginate)
- `POST /agent/pipeline/{card_id}/approve` — triggers tailor if needed, creates Application
- `POST /agent/pipeline/{card_id}/dismiss`
- `POST /agent/chat` — full response at once (frontend simulates streaming)

**Module responsibilities:**
- `jobs/router.py` — thin routes
- `jobs/sources.py` — JSearch (RapidAPI) client with `httpx`. Dedupe by `(title, company,
  source_url)` before upserting into global `jobs/`. Cache lookups: don't re-fetch the same
  query within 1 hour.
- `jobs/matcher.py` — **Claude Haiku** LLM-judge. Input: `ResumeJSON` + `Job`. Output:
  `{ match_score: 0-100, matched_skills, missing_skills, why, category }`. Keep the prompt
  TIGHT — this runs 20+ times per brief. Use structured output (tool use or JSON mode).
- `agent/router.py` — thin routes
- `agent/reasoner.py` — Brief pipeline as a `BackgroundTask`:
  1. Load user's active `ResumeJSON`
  2. Pull 20-30 new jobs via `jobs.sources.search()` using user's `role`
  3. For each job, call `matcher.match()` (parallel with `asyncio.gather`, but throttle
     to ~5 concurrent to avoid Anthropic rate limits)
  4. Write `PipelineCard` per match into `users/{uid}/pipeline/`
  5. Update `briefs/{brief_id}` status throughout with `progress: {current, total}`
- `agent/chat.py` — `POST /agent/chat`. **Claude Opus** with tool use. Loads the last N
  messages of the conversation as context. Streams internally but returns the final
  message at once. Writes new `PipelineCard`s if the agent searches jobs.
- `agent/tools.py` — Anthropic tool definitions: `search_jobs`, `get_resume`, `tailor_resume`,
  `get_pipeline`. Tools call internal functions, not HTTP endpoints.

**Dependencies from C:**
- `app/deps.py::current_user`
- `app/schemas.py` — `Job`, `PipelineCard`, `Application`, `ChatMessage`, `ResumeJSON`
- `app/llm.py` — `llm.haiku()`, `llm.opus()`, tool-use helpers
- `app/firebase.py` — `db`

**Cross-team coupling:**
- Approve flow calls into Person A's `tailor` if `card.tailored_resume_id` is null. Use the
  `POST /resumes/{id}/tailor` endpoint internally OR call `resumes.tailor.run()` directly
  (preferred — avoid HTTP self-calls). Coordinate with A on the function signature.

**Day 1 (while waiting on C):** write the matcher prompt + structured-output schema with
direct Anthropic SDK calls. Get a stable `match_score` on 10 hand-picked job/resume pairs.

**Watch out for:**
- LLM cost. Brief calls Haiku 30x. Don't accidentally use Opus in the matcher.
- Concurrency. `asyncio.gather` with no semaphore will get you rate-limited. Cap at ~5.
- Tool use loop in `chat.py` — set a max-iterations guard so the agent can't loop forever.
- `auto_submit=true` in approve: for v1, just create the Application — actually submitting
  is out of scope.

---

## Person C — Platform + Tracker

**You are the unblocker.** A and B are stuck until you ship `schemas.py`, `deps.py`,
`firebase.py`, `llm.py`. Do those Day 1.

**You own:**
- `backend/app/main.py`, `config.py`, `firebase.py`, `deps.py`, `schemas.py`, `llm.py`,
  `auth.py`, `applications/`
- `backend/Dockerfile`, `backend/pyproject.toml`, Railway deployment
- Firestore Security Rules (separate `firestore.rules` file at repo root or `backend/`)

**Endpoints to ship:**
- `GET /health` (§3.1)
- `POST /auth/session`, `GET/PATCH/DELETE /users/me` (§3.2)
- `GET /applications`, `GET /applications/{id}`, `PATCH /applications/{id}` (§3.6)

**Module responsibilities (in priority order):**

**Day 1 (unblocks A and B — do these FIRST):**
- `schemas.py` — All shared Pydantic models from contract §2: `User`, `Resume`, `ResumeJSON`,
  `Job`, `PipelineCard`, `Application`, `ChatMessage`. Match field names exactly.
- `config.py` — `pydantic-settings` reading `.env`. Fields: `firebase_credentials_path`,
  `anthropic_api_key`, `rapidapi_key`, `llm_model_cheap`, `llm_model_strong`, `env`,
  `allowed_origins`.
- `firebase.py` — Init `firebase-admin` with service account JSON. Export `db` (Firestore
  AsyncClient), `storage_bucket`, `verify_id_token(token) -> uid`.
- `deps.py` — `current_user: Annotated[User, Depends(get_current_user)]` that:
  reads `Authorization: Bearer ...` → verifies via `firebase.verify_id_token` → loads
  user doc from Firestore → returns `User`. Cache per-request.
- `llm.py` — `class LLM` with `haiku(messages, **kw)`, `strong(messages, **kw)`,
  `opus_with_tools(messages, tools, **kw)`. Reads model IDs from `config`. Handles retries
  with exponential backoff on 429/529. Logs token counts.

**Day 2+:**
- `main.py` — FastAPI app, mount all routers, CORS from `config.allowed_origins`, global
  exception handler producing the error shape from contract §1.
- `auth.py` — `/auth/session` creates user doc on first call (idempotent, transaction).
  `/users/me` CRUD on `users/{uid}`.
- `applications/router.py` — `users/{uid}/applications/` CRUD. `status` enum from contract.
- `Dockerfile` — Multi-stage: Python 3.12 slim + Tectonic binary (download from GitHub
  release in build stage, copy to runtime). Run with `uvicorn` on `$PORT`.
- Railway setup — env vars, build command (`uv sync --frozen`), start command.
- `firestore.rules` — Deny-all default. Allow read/write on `users/{uid}/**` only where
  `request.auth.uid == uid`. Allow read on `jobs/{any}` for authenticated users.

**Rate limiting:** centralize in `deps.py` as `rate_limit(endpoint_key, daily_cap)`
dependency. Caps from contract §1.

**Dependencies on others:** none. You're the foundation.

**Watch out for:**
- **Coordinate the `schemas.py` API early.** Ping A and B in chat the moment it's drafted.
  Field rename mid-week = pain for everyone.
- Don't bake the LLM client per-call. Single `LLM` instance, reused.
- Firestore Security Rules are NOT optional. Even with backend filtering, if your service
  account leaks, rules are the last line of defense.
- Railway cold starts. Tectonic on cold start is brutal — keep one instance always warm.

---

## Coordination

| Person | Blocks | Blocked by |
|---|---|---|
| C | A, B | nothing |
| A | nothing | C (Day 1 modules) |
| B | nothing | C (Day 1 modules), A (tailor function signature) |

**Daily 10-min sync:** what shipped, what's blocked, any contract changes.
**Contract changes:** PR to `docs/api-contract.md` first, +1 from at least one other
person, then code.
**Merge cadence:** open PR into `daryn/backend` when feature is endpoint-complete (route +
logic + happy-path manual test). Don't sit on branches >2 days.
