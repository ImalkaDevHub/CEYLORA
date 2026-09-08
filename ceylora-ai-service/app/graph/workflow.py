"""LangGraph workflow for the CEYLORA AI service.

Full chain:  planner -> destination -> budget_availability -> validation_safety -> END

  - planner:             LLM (Gemini) draft itinerary, with a stub fallback.
  - destination:         real destination rows pulled from the CEYLORA .NET
                         API's internal endpoint (the first real tool call).
  - budget_availability: deterministic cost estimate + budget-overrun flag.
  - validation_safety:   deterministic PASS/NEEDS_REVISION checks + the
                         `requires_approval` flag the .NET human-approval gate
                         reads before any auto-confirm.

All four required agents are now chained. The next piece is the human-approval
gate on the .NET side, which hooks into `validation_safety`'s output.
"""

from __future__ import annotations

from typing import Any, TypedDict

from langgraph.graph import END, START, StateGraph

from app.agents.budget_availability_agent import budget_availability_node
from app.agents.destination_agent import destination_node
from app.agents.planner_agent import planner_node
from app.agents.validation_safety_agent import validation_safety_node


class PlannerState(TypedDict, total=False):
    """Shared state passed between graph nodes.

    Every node reads and writes this one dict.
    """

    # inputs
    goal: str
    days: int
    budget: float
    interests: list[str]
    # planner output
    plan: str
    generated_by: str
    # destination output
    candidate_destinations: list[dict[str, Any]]
    # budget_availability output
    budget_breakdown: dict[str, Any]
    # validation_safety output
    validation_results: list[dict[str, Any]]
    overall_status: str
    requires_approval: bool


def _build_graph():
    graph = StateGraph(PlannerState)

    graph.add_node("planner", planner_node)
    graph.add_node("destination", destination_node)
    graph.add_node("budget_availability", budget_availability_node)
    graph.add_node("validation_safety", validation_safety_node)

    graph.add_edge(START, "planner")
    graph.add_edge("planner", "destination")
    graph.add_edge("destination", "budget_availability")
    graph.add_edge("budget_availability", "validation_safety")
    graph.add_edge("validation_safety", END)

    return graph.compile()


# Compile once at import time; the compiled graph is reusable and stateless.
_compiled_graph = _build_graph()


def run_workflow(input_state: dict[str, Any]) -> dict[str, Any]:
    """Execute the compiled workflow and return the final state as a plain dict."""
    result = _compiled_graph.invoke(input_state)
    return dict(result)
