"""Inbound request schemas for the CEYLORA AI service.

These model the payloads the .NET API sends over HTTP. The AI service never
talks to the database, so every value it needs must arrive in the request body.
"""

from pydantic import BaseModel, Field


class PlanRequest(BaseModel):
    """Body for POST /api/workflow/plan."""

    goal: str = Field(
        ...,
        min_length=1,
        description="Free-text description of what the traveler wants, e.g. "
        "'Relaxed south-coast beach trip with some wildlife'.",
    )
    days: int = Field(..., gt=0, le=60, description="Trip length in days.")
    budget: float = Field(..., ge=0, description="Total budget in LKR.")
    interests: list[str] = Field(
        default_factory=list,
        description="Optional interest tags, e.g. ['beach', 'wildlife', 'culture'].",
    )

    model_config = {
        "json_schema_extra": {
            "example": {
                "goal": "Relaxed south-coast beach trip with some wildlife",
                "days": 5,
                "budget": 120000,
                "interests": ["beach", "wildlife"],
            }
        }
    }
