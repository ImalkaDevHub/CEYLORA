"""LangGraph workflow for the CEYLORA AI service.

Full chain:  planner -> destination -> budget_availability -> validation_safety -> END

  - planner:             LLM (Gemini) draft itinerary, with a stub fallback.
  - destination:         real destination rows pulled from the CEYLORA .NET
                         API's internal endpoint (the first real tool call).
  - budget_availability: deterministic cost estimate + budget-overrun flag.
  - validation_safety:   deterministic PASS/NEEDS_REVISION checks + the
                         `requires_approval` flag the .NET human-approval gate
                         reads before any auto-confirm.

`run_workflow_with_steps` streams the graph so each node's contribution is
captured as an execution record; the .NET API persists those as
AIWorkflowStep rows, which is what makes the chain observable after the fact.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, TypedDict

from langgraph.graph import END, START, StateGraph

from app.agents.budget_availability_agent import budget_availability_node
from app.agents.destination_agent import destination_node
from app.agents.planner_agent import planner_node
from app.agents.validation_safety_agent import validation_safety_node

logger = logging.getLogger("ceylora.graph.workflow")

_SUMMARY_LIMIT = 150

# Declared execution order — used only to attribute a failure to the node that
# was next in line when the stream raised.
_NODE_ORDER = ("planner", "destination", "budget_availability", "validation_safety")


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


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


def _truncate(text: str, limit: int = _SUMMARY_LIMIT) -> str:
    text = " ".join(text.split())  # collapse newlines so summaries stay one line
    return text if len(text) <= limit else text[: limit - 1].rstrip() + "…"


def _compact(value: Any) -> str:
    """Render one output field compactly enough to sit inside a 150-char summary."""
    if isinstance(value, list):
        names = [v.get("name") for v in value if isinstance(v, dict) and v.get("name")]
        if names:
            return "[" + ", ".join(str(n) for n in names) + "]"
        return f"[{len(value)} item(s)]"
    if isinstance(value, dict):
        head = list(value.items())[:4]
        return "{" + ", ".join(f"{k}: {v}" for k, v in head) + "}"
    return str(value)


def _summarize(update: dict[str, Any], previous_plan: str) -> str | None:
    """Summarize what a node contributed.

    Prefers the text this node appended to `plan` (every agent appends rather
    than replaces, apart from the planner which writes it first). Falls back to
    the node's other output fields when it didn't touch `plan`.
    """
    plan = update.get("plan")
    if isinstance(plan, str) and plan:
        delta = plan[len(previous_plan):] if plan.startswith(previous_plan) else plan
        delta = delta.strip()
        if delta:
            return _truncate(delta)

    others = {k: v for k, v in update.items() if k != "plan"}
    if others:
        return _truncate(", ".join(f"{k}={_compact(v)}" for k, v in others.items()))
    return None


def run_workflow_with_steps(
    input_state: dict[str, Any],
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Execute the graph and return `(final_state, steps)`.

    `steps` holds one record per node that ran, in execution order. If the
    stream raises part-way, whatever completed is still returned alongside an
    `error` step — consistent with the never-hard-fail contract the agents
    themselves follow.
    """
    steps: list[dict[str, Any]] = []
    final_state: dict[str, Any] = dict(input_state)
    previous_plan = str(input_state.get("plan", "") or "")
    step_started = _utcnow()

    try:
        for mode, chunk in _compiled_graph.stream(
            input_state, stream_mode=["updates", "values"]
        ):
            if mode == "values":
                # Full merged state after the step that just ran; the last one wins.
                final_state = dict(chunk)
                continue

            # mode == "updates": {node_name: partial_state_update}
            for node_name, update in (chunk or {}).items():
                update = update or {}
                completed = _utcnow()
                steps.append(
                    {
                        "agent": node_name,
                        "status": "completed",
                        "started_at": step_started,
                        "completed_at": completed,
                        "output_summary": _summarize(update, previous_plan),
                        "error_message": None,
                    }
                )
                new_plan = update.get("plan")
                if isinstance(new_plan, str):
                    previous_plan = new_plan
                step_started = completed

    except Exception as exc:
        ran = {s["agent"] for s in steps}
        failed_agent = next((n for n in _NODE_ORDER if n not in ran), "unknown")
        logger.exception("run_workflow_with_steps: graph failed at %r", failed_agent)
        steps.append(
            {
                "agent": failed_agent,
                "status": "error",
                "started_at": step_started,
                "completed_at": _utcnow(),
                "output_summary": None,
                "error_message": f"{type(exc).__name__}: {exc}",
            }
        )

    return final_state, steps


def run_workflow(input_state: dict[str, Any]) -> dict[str, Any]:
    """Execute the compiled workflow and return the final state as a plain dict.

    Kept for callers that don't need per-step records.
    """
    final_state, _ = run_workflow_with_steps(input_state)
    return final_state
