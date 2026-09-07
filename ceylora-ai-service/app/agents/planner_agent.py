"""Planner agent — dummy LangGraph node.

This is a stub. It does NOT call an LLM. Its only job right now is to prove that
a LangGraph node executes inside the compiled workflow and produces output that
flows back out over HTTP. Real prompt/LLM logic replaces the body of
`planner_node` later.
"""

from __future__ import annotations

from typing import Any


def _stub_itinerary(goal: str, days: int, budget: float, interests: list[str]) -> str:
    """Build a fixed, deterministic itinerary string from the input state."""
    per_day = budget / days if days else budget
    interest_line = ", ".join(interests) if interests else "general sightseeing"

    lines = [
        f"Draft plan for: {goal}",
        f"Duration: {days} day(s) | Budget: LKR {budget:,.0f} (~LKR {per_day:,.0f}/day)",
        f"Focus: {interest_line}",
        "",
    ]
    sample_stops = [
        "Arrival, settle in, sunset walk on the beach",
        "Wildlife safari in the morning, local seafood lunch",
        "Cultural site visit and village tour",
        "Free day: snorkeling or spa, optional day trip",
        "Slow morning, souvenir shopping, departure",
    ]
    for day in range(1, days + 1):
        stop = sample_stops[(day - 1) % len(sample_stops)]
        lines.append(f"Day {day}: {stop}")

    lines.append("")
    lines.append("(Stubbed itinerary — generated without an LLM.)")
    return "\n".join(lines)


def planner_node(state: dict[str, Any]) -> dict[str, Any]:
    """LangGraph node.

    Takes the workflow state dict (expects keys: goal, days, budget, and
    optionally interests) and returns a partial state update containing `plan`.
    """
    goal = state.get("goal", "Unspecified trip")
    days = int(state.get("days", 1))
    budget = float(state.get("budget", 0.0))
    interests = list(state.get("interests", []) or [])

    plan_text = _stub_itinerary(goal, days, budget, interests)

    return {
        "plan": plan_text,
        "generated_by": "planner_agent (stub)",
    }
