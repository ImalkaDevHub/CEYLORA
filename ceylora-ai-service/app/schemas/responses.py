"""Outbound response schemas for the CEYLORA AI service.

The .NET API is responsible for persisting anything returned here; this service
holds no state of its own.
"""

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str = "ok"
    service: str = "ceylora-ai-service"


class PlanResponse(BaseModel):
    """Result of the planner workflow.

    `plan` is currently a hardcoded stub itinerary — no LLM is involved yet.
    """

    goal: str
    days: int
    budget: float
    interests: list[str] = Field(default_factory=list)
    plan: str = Field(..., description="Human-readable itinerary text.")
    generated_by: str = Field(
        default="planner_agent (stub)",
        description="Marker so callers can tell this is not yet LLM-generated.",
    )
