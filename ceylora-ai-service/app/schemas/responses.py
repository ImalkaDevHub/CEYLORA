"""Outbound response schemas for the CEYLORA AI service.

The .NET API is responsible for persisting anything returned here; this service
holds no state of its own.
"""

from datetime import datetime

from pydantic import BaseModel, Field


class HealthResponse(BaseModel):
    status: str = "ok"
    service: str = "ceylora-ai-service"


class WorkflowStep(BaseModel):
    """One agent's execution record within a single workflow run.

    The .NET API persists these as AIWorkflowStep rows — this is what makes the
    agent chain observable after the fact.
    """

    agent: str = Field(..., description="Graph node name, e.g. 'planner'.")
    status: str = Field(..., description="'completed' or 'error'.")
    started_at: datetime
    completed_at: datetime | None = None
    output_summary: str | None = Field(
        default=None,
        description="Short (<=150 chars) summary of what this agent contributed.",
    )
    error_message: str | None = None


class PlanResponse(BaseModel):
    """Result of the planner workflow."""

    goal: str
    days: int
    budget: float
    interests: list[str] = Field(default_factory=list)
    # No max_length constraint — carries the full LLM-generated itinerary,
    # which can run to several hundred words.
    plan: str = Field(..., description="Human-readable itinerary text.")
    generated_by: str = Field(
        default="planner_agent (stub)",
        description=(
            "Which path produced `plan`: 'planner_agent (gemini)', "
            "'planner_agent (stub-fallback)', or 'planner_agent (stub)'."
        ),
    )

    # --- added alongside the fields above; nothing existing was removed ---
    overall_status: str = Field(
        default="Pending",
        description="Verdict from validation_safety: 'PASS' or 'NEEDS_REVISION'.",
    )
    requires_approval: bool = Field(
        default=False,
        description=(
            "Whether a human operator must approve before this plan may be "
            "confirmed. Enforced by the .NET backend, never by the AI itself."
        ),
    )
    steps: list[WorkflowStep] = Field(
        default_factory=list,
        description="Per-agent execution records, in the order the graph ran them.",
    )
