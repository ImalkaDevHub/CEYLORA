"""CEYLORA AI Service — FastAPI entrypoint.

Thin vertical slice for Component D (agentic AI). Boots a FastAPI app, exposes a
health check and a single planning endpoint backed by a one-node LangGraph
workflow. No LLM calls, no database access.
"""

from __future__ import annotations

from dotenv import load_dotenv
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.graph.workflow import run_workflow
from app.schemas.requests import PlanRequest
from app.schemas.responses import HealthResponse, PlanResponse

# Loads .env if present. Nothing in it is consumed yet (see .env.example).
load_dotenv()

app = FastAPI(
    title="CEYLORA AI Service",
    description=(
        "LangGraph-based agentic AI subsystem for CEYLORA. Called by the "
        "ASP.NET Core API over HTTP; holds no database connection of its own."
    ),
    version="0.1.0",
)

# Local dev: allow all origins. Tighten before any non-local deployment.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health", response_model=HealthResponse, tags=["meta"])
def health() -> HealthResponse:
    return HealthResponse(status="ok", service="ceylora-ai-service")


@app.post("/api/workflow/plan", response_model=PlanResponse, tags=["workflow"])
def plan(request: PlanRequest) -> PlanResponse:
    """Run the planner workflow for a trip request.

    The .NET API sends the goal/days/budget/interests it already holds; this
    service runs the graph and returns an itinerary for .NET to persist.
    """
    result = run_workflow(request.model_dump())

    return PlanResponse(
        goal=request.goal,
        days=request.days,
        budget=request.budget,
        interests=request.interests,
        plan=result.get("plan", ""),
        generated_by=result.get("generated_by", "planner_agent (stub)"),
    )
