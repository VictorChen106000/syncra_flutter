# Syncra Backend

FastAPI + Firestore + Tectonic LaTeX. See `../docs/api-contract.md` for the API spec.

## Ownership

| Folder | Owner |
|---|---|
| `app/main.py`, `app/firebase.py`, `app/deps.py`, `app/config.py`, `app/llm.py`, `app/schemas.py` | C |
| `app/auth.py`, `app/applications/` | C |
| `app/resumes/` | A |
| `app/jobs/`, `app/agent/` | B |

## Local setup

```bash
uv sync
cp .env.example .env  # fill in keys
uv run uvicorn app.main:app --reload --port 8000
```
