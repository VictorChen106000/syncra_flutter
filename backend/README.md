# Syncra Backend

FastAPI + Firestore + Anthropic Claude + Tectonic. Source of truth for API shapes: [`../docs/api-contract.md`](../docs/api-contract.md).

---

## TL;DR — what's working as of 2026-05-13

**End-to-end live:** auth, user CRUD, application tracker, **agent brief pipeline (passive mode)**, jobs search.

- ✅ `POST /auth/session` + `/users/me` (CRUD) — tested with real Firebase ID tokens
- ✅ `GET/PATCH /applications` — owner-scoped reads, status updates
- ✅ `POST /agent/brief` → background task → `GET /agent/brief/{id}` polling → `GET /agent/pipeline` cards
- ✅ `POST /jobs/search`, `GET /jobs/{id}` — JSearch via RapidAPI, deduped + upserted to global `jobs/`
- ✅ Firebase Auth token verification, Firestore Security Rules deployed (deny-all + owner-only)
- ✅ Contract error shape on every endpoint, 401 gating verified

**Not yet:**

- ⛔️ `agent/chat.py` + `agent/tools.py` — active-mode chatbot (next backend task)
- ⛔️ Person A's `resumes/` — parser, tailor, download — all stubs
- ⛔️ Frontend wire-up — Flutter app currently uses mocks; `lib/core/network/api_client.dart` is unimplemented
- ⛔️ Railway deploy — Dockerfile is ready, dashboard config pending

---

## Ownership (per `docs/team-briefs.md`)

| Folder / file | Owner |
|---|---|
| `app/main.py`, `firebase.py`, `deps.py`, `config.py`, `llm.py`, `schemas.py`, `auth.py`, `applications/` | C |
| `app/resumes/` (parser, tailor, latex, storage→removed) | A |
| `app/jobs/`, `app/agent/` | B *(currently ghost-written by C; see file headers)* |
| `Dockerfile`, `firestore.rules`, `firebase.json` | C |

**Cross-folder edits violate team policy. If you need a shared type, PR to `app/schemas.py` (C's).**

---

## Local setup

### 1) Install deps

```bash
cd backend
uv sync
```

### 2) Get keys & credentials

You need three things in your environment:

1. **Firebase Admin service-account JSON** — Firebase Console → ⚙️ Project Settings → Service Accounts → "Generate new private key". Save it as `backend/firebase_credentials.json` (already in `.gitignore`).
2. **Anthropic API key** — console.anthropic.com → API Keys → Create. Starts with `sk-ant-api03-…`.
3. **RapidAPI key with JSearch enabled** — rapidapi.com → search "JSearch" → subscribe to free plan → copy `X-RapidAPI-Key`.

### 3) Fill in `.env`

```bash
cp .env.example .env
# Then edit .env, replacing the `...` placeholders for ANTHROPIC_API_KEY and RAPIDAPI_KEY.
```

### 4) Run

```bash
uv run uvicorn app.main:app --reload --port 8000
```

Health check:

```bash
curl http://localhost:8000/api/v1/health
# → {"status":"ok","version":"0.1.0"}
```

Interactive API docs at <http://localhost:8000/docs>.

---

## End-to-end agent test (passive mode)

This proves brief + matcher + sources + Firestore + auth all work together.

```bash
# 1) Mint a Firebase ID token for a test user
API_KEY="AIzaSyDazABtqDFMWnSbno3O7o9ORXUiCWOs8dk"   # web key from android/app/google-services.json
TOKEN=$(curl -s -X POST \
  "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=$API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"email":"YOUR_TEST@EMAIL.com","password":"YOUR_PASSWORD","returnSecureToken":true}' \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['idToken'])")

# 2) Make sure the user has a Firestore doc (idempotent)
curl -s -X POST http://localhost:8000/api/v1/auth/session \
  -H "Authorization: Bearer $TOKEN"

# 3) Set a role so the brief queries something specific
curl -s -X PATCH http://localhost:8000/api/v1/users/me \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"role":"UX Designer"}'

# 4) Seed a fake ResumeJSON until A ships /resumes/upload.
#    (Until then, write directly to Firestore at users/{uid}/resumes/{id}/parsed/parsed.)

# 5) Kick off the brief
curl -s -X POST http://localhost:8000/api/v1/agent/brief \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"force":true}'
# → {"brief_id":"brief_…","status":"pending","poll_url":"/api/v1/agent/brief/brief_…"}

# 6) Poll until status=done (typically ~30s for 10 jobs)
curl -s http://localhost:8000/api/v1/agent/brief/<brief_id> \
  -H "Authorization: Bearer $TOKEN"

# 7) View the pipeline
curl -s http://localhost:8000/api/v1/agent/pipeline?limit=5 \
  -H "Authorization: Bearer $TOKEN"
```

You can also check the Firebase Console → Firestore Database → `users/{uid}/pipeline/` to see the cards visually.

---

## Architecture map

```
app/
├── main.py            FastAPI app, CORS, global error handler, router mounting
├── config.py          pydantic-settings reading .env
├── firebase.py        Firebase Admin init (lazy), Firestore AsyncClient, verify_id_token
├── deps.py            current_user / verified_uid dependencies, rate_limit factory
├── llm.py             Anthropic wrapper: haiku(), strong(), opus_with_tools()
├── schemas.py         All shared Pydantic models — the cross-team contract
├── auth.py            POST /auth/session, /users/me CRUD
├── applications/
│   └── router.py      Application tracker (list/get/patch)
├── jobs/
│   ├── sources.py     JSearch HTTP client + 1h cache + dedupe + upsert
│   ├── matcher.py     Claude Haiku LLM-judge with tool-use structured output
│   └── router.py      GET /jobs/{id}, POST /jobs/search
├── agent/
│   ├── reasoner.py    Brief pipeline (background): load resume → search → match 5-at-once → write cards
│   ├── router.py      Brief + pipeline + approve/dismiss endpoints
│   ├── chat.py        ⛔️ NOT WRITTEN — active-mode chatbot (next backend task)
│   └── tools.py       ⛔️ NOT WRITTEN — Anthropic tool definitions for chat
└── resumes/           ⛔️ Person A's territory — currently stubs
```

---

## Key decisions baked in (read these before changing things)

### 1) No Firebase Cloud Storage (contract v0.3)

Resumes are stored ONLY as structured `ResumeJSON` in Firestore. PDFs are re-rendered on demand from `ResumeJSON` via the planned `GET /resumes/{id}/download`. Reason: Cloud Storage now requires Firebase's paid Blaze plan with a credit card. This keeps the project on the free Spark tier.

**What it means for A:** no `storage.py`, no signed URLs, no upload-to-bucket plumbing. Parse the PDF, save the JSON, throw the bytes away.

### 2) No public match score on PipelineCard (contract v0.4)

We removed `match_score: int` from the `PipelineCard` shape. Matching is tier-based only via `category`: `ready` | `input_needed` | `exploration` (LinkedIn-style: strong / partial / stretch). The matcher still computes an internal 0-100 score used by `reasoner.py` for sort order only — never surfaced.

Reason: a number implies false precision the LLM can't deliver; tiers make decisions clearer; LinkedIn already proved the UX.

### 3) Long-running tasks are polled, not streamed

`POST /agent/brief` returns 202 immediately with a `poll_url`. Frontend polls `GET /agent/brief/{id}` every ~2s. No SSE, no WebSockets. Same for resume tailoring (when A ships it).

### 4) Owner-only authorization

Every user-scoped query filters by `current_user.uid`. Firestore Security Rules in `firestore.rules` enforce this at the DB level too (defense in depth — if the service account leaks, users still can't access each other's data).

### 5) Cost discipline

- Haiku for matching (cheap, called ~25× per brief).
- Opus reserved for resume tailoring (called 1× when user approves) and chat reasoning.
- Per-user daily caps in `users/{uid}/usage/{YYYY-MM-DD}`: brief=12, tailor=20, chat=30, upload=20.

---

## For the frontend dev picking this up

You can stop using mocks and point at this backend whenever you're ready.

1. Add `dio: ^5.7.0` to `pubspec.yaml`.
2. Implement [`lib/core/network/api_client.dart`](../lib/core/network/api_client.dart) (currently throws `UnimplementedError`). It needs to:
   - Read `await FirebaseAuth.instance.currentUser?.getIdToken()` before every call.
   - Send `Authorization: Bearer <token>` header.
3. Base URL: `http://localhost:8000/api/v1` (iOS simulator), `http://10.0.2.2:8000/api/v1` (Android emulator), or Railway URL in prod.
4. Replace mock data calls screen by screen:
   - Dashboard pipeline → `GET /agent/pipeline`
   - Trigger brief → `POST /agent/brief` then poll `GET /agent/brief/{id}`
   - Jobs detail → use card data already in pipeline (no extra fetch needed)
   - Approve → `POST /agent/pipeline/{card_id}/approve`
   - Dismiss → `POST /agent/pipeline/{card_id}/dismiss`
   - Tracker → `GET /applications`, `PATCH /applications/{id}`
5. Error shape: every backend error returns `{"error": {"type": "...", "message": "...", "status_code": N}}`. Surface `message` to users on non-200.

---

## Open todos

- [ ] `agent/chat.py` + `agent/tools.py` — active-mode chatbot (B's scope; next backend task)
- [ ] Person A: `resumes/parser.py`, `resumes/tailor.py`, `resumes/latex.py`, `resumes/router.py`, `resumes/download` endpoint
- [ ] Railway deploy
- [ ] Matcher prompt tuning — current rubric tends to be conservative; all 10 cards in our smoke test came back as `exploration`. Worth running real briefs against varied resumes and adjusting thresholds.
- [ ] Frontend wire-up (see above)
- [ ] Replace the in-memory query cache in `jobs/sources.py` with something persistent if Railway cold-starts become a problem.

---

## How to contribute

- One PR per feature, into `main` (or whatever the team's integration branch is — `daryn/backend` was the original target but has been merged).
- Contract changes (`docs/api-contract.md`) need a +1 from at least one other person before code.
- Stay in your folder. If a shared type needs to change, open a focused PR on `schemas.py`.

Questions? See [`docs/team-briefs.md`](../docs/team-briefs.md) for the original handoff.
