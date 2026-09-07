"""Minimal LangGraph workflow.

Single node (the planner) wired as both entry and exit point. This exists to
prove the graph compiles and executes end to end. More nodes (research,
budgeting, review) get chained here as the other agents are built.
"""

from __future__ import annotations

from typing import Any, TypedDict

from langgraph.graph import END, START, StateGraph

from app.agents.planner_agent import planner_node


class PlannerState(TypedDict, total=False):
    """Shared state passed between graph nodes."""

    goal: str
    days: int
    budget: float
    interests: list[str]
    plan: str
    generated_by: str


def _build_graph():
    graph = StateGraph(PlannerState)
    graph.add_node("planner", planner_node)
    graph.add_edge(START, "planner")
    graph.add_edge("planner", END)
    return graph.compile()


# Compile once at import time; the compiled graph is reusable and stateless.
_compiled_graph = _build_graph()


def run_workflow(input_state: dict[str, Any]) -> dict[str, Any]:
    """Execute the compiled workflow and return the final state as a plain dict."""
    result = _compiled_graph.invoke(input_state)
    return dict(result)
