# ceylora-ai-service

LangGraph-based **agentic AI subsystem** for the CEYLORA platform.

## What this service is

A standalone Python (FastAPI) microservice that runs LangGraph agent workflows —
starting with a trip **planner**. It turns a structured trip request
(goal, days, budget, interests) into an itinerary.

Right now it is a **thin vertical slice**: one dummy agent, one graph node, no
real LLM call. Its purpose is to prove that the service boots, the graph
executes, and a result comes back over HTTP. The real planner/research/budget/
review agents are added against this skeleton later.

## How it fits into the architecture

```
        ┌─────────────┐        ┌──────────────────────┐        ┌──────────────┐
Client →│  ASP.NET     │  HTTP  │  ceylora-ai-service   │        │  (future)    │
        │  Core API     ├───────►│  FastAPI + LangGraph   ├───────►│  LLM provider │
        │  (auth + DB)  │◄───────┤  planner workflow      │        │              │
        └──────┬────────┘  JSON  └──────────────────────┘        └──────────────┘
               │
        ┌──────▼──────┐
        │ PostgreSQL   │
        │ (Supabase)   │
        └─────────────┘
```

- **The .NET API is the only caller.** Clients (React / Flutter) never hit this
  service directly.
- **No direct database access.** This service opens no DB connection. Everything
  it needs arrives in the request body; everything it produces is returned to
  .NET, which owns persistence and auth.
- **Stateless.** The compiled graph is reusable and holds no per-request state.

One-sentence rationale: *LangGraph's agent orchestration lives in Python because
that is where the mature tooling is; keeping it in a separate service means the
.NET API stays the single source of truth for data and auth.*

## Endpoints

| Method | Path                   | Description                                  |
|--------|------------------------|----------------------------------------------|
| GET    | `/health`              | Liveness check. `{"status":"ok","service":"ceylora-ai-service"}` |
| POST   | `/api/workflow/plan`   | Run the planner workflow, return an itinerary |
| GET    | `/docs`                | Interactive OpenAPI docs (FastAPI default)    |

### `POST /api/workflow/plan`

Request body:

```json
{
  "goal": "Relaxed south-coast beach trip with some wildlife",
  "days": 5,
  "budget": 120000,
  "interests": ["beach", "wildlife"]
}
```

Response body:

```json
{
  "goal": "Relaxed south-coast beach trip with some wildlife",
  "days": 5,
  "budget": 120000.0,
  "interests": ["beach", "wildlife"],
  "plan": "Draft plan for: ...\nDay 1: ...\n(Stubbed itinerary — generated without an LLM.)",
  "generated_by": "planner_agent (stub)"
}
```

## Project layout

```
ceylora-ai-service/
  app/
    main.py              FastAPI app: CORS, /health, /api/workflow/plan
    agents/
      planner_agent.py   Dummy LangGraph node (stub itinerary, no LLM)
    graph/
      workflow.py         Minimal StateGraph: one node, entry == exit; run_workflow()
    schemas/
      requests.py         PlanRequest (Pydantic)
      responses.py        HealthResponse, PlanResponse (Pydantic)
  requirements.txt
  .env.example
  README.md
```

## Setup

Requires **Python 3.11+**.

```bash
cd ceylora-ai-service

# 1. Virtual environment
python -m venv .venv
# Windows (PowerShell):
.venv\Scripts\Activate.ps1
# macOS / Linux:
source .venv/bin/activate

# 2. Dependencies
pip install -r requirements.txt

# 3. Environment file (optional — nothing in it is used yet)
cp .env.example .env

# 4. Run
uvicorn app.main:app --reload --port 8001
```

Service is then at `http://localhost:8001` (`/docs` for Swagger UI).

## Quick check

```bash
curl http://localhost:8001/health

curl -X POST http://localhost:8001/api/workflow/plan \
  -H "Content-Type: application/json" \
  -d '{"goal":"Relaxed south-coast beach trip","days":5,"budget":120000,"interests":["beach","wildlife"]}'
```

## Not implemented yet

- Real LLM calls (the `ANTHROPIC_API_KEY` placeholder in `.env.example` is unused).
- The other three agents (research, budgeting, review).
- Auth on the endpoints (the .NET API is trusted as the sole caller for now).
