"""LangGraph workflow for the CEYLORA AI service.

Current chain:  planner -> destination -> END

  - planner:     LLM (Gemini) draft itinerary, with a stub fallback.
  - destination: real destination rows pulled from the CEYLORA .NET API's
                 internal endpoint (the first real tool call in the chain).

The remaining two agents (budget_availability, validation_safety) get chained
on after `destination` — see the comment in `_build_graph`.
"""

from __future__ import annotations

from typing import Any, TypedDict

from langgraph.graph import END, START, StateGraph

from app.agents.destination_agent import destination_node
from app.agents.planner_agent import planner_node


class PlannerState(TypedDict, total=False):
    """Shared state passed between graph nodes.

    Every node reads and writes this one dict. As the remaining agents land,
    add their output keys here (e.g. `budget_breakdown`, `validation_notes`).
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


def _build_graph():
    graph = StateGraph(PlannerState)

    graph.add_node("planner", planner_node)
    graph.add_node("destination", destination_node)

    graph.add_edge(START, "planner")
    graph.add_edge("planner", "destination")
    graph.add_edge("destination", END)

    # ------------------------------------------------------------------
    # NEXT: chain the remaining two agents after "destination", in sequence.
    #
    #   from app.agents.budget_availability_agent import budget_availability_node
    #   from app.agents.validation_safety_agent import validation_safety_node
    #
    #   graph.add_node("budget_availability", budget_availability_node)
    #   graph.add_node("validation_safety", validation_safety_node)
    #
    #   graph.add_edge("destination", "budget_availability")
    #   graph.add_edge("budget_availability", "validation_safety")
    #   graph.add_edge("validation_safety", END)
    #
    # (Remove the direct "destination" -> END edge above when the chain grows.)
    # ------------------------------------------------------------------

    return graph.compile()


# Compile once at import time; the compiled graph is reusable and stateless.
_compiled_graph = _build_graph()


def run_workflow(input_state: dict[str, Any]) -> dict[str, Any]:
    """Execute the compiled workflow and return the final state as a plain dict."""
    result = _compiled_graph.invoke(input_state)
    return dict(result)
