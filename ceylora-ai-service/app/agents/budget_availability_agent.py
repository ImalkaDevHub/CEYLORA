"""Budget & Availability agent — third node in the chain.

Estimates a cost breakdown for the candidate trip using a deterministic
rate table (accommodation/activities/transport/food), rather than a live
pricing lookup — the Experience catalog isn't built yet, so this is the
allow-listed "tool" this agent uses until real experience pricing exists.

Same safety contract as the other agents: any unexpected failure is caught,
logged, and degraded to a safe zero-cost stub — the graph never crashes.
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger("ceylora.agents.budget_availability")

# Deterministic per-day baseline rates (LKR), by TravelCategory.
# These are placeholder estimates for MVP scope — swap for real Experience
# pricing once that catalog exists on the .NET side.
_ACCOMMODATION_DAILY_RATE: dict[str, float] = {
    "beach": 18000,
    "nature": 12000,
    "culture": 10000,
    "adventure": 14000,
    "wildlife": 20000,
    "citylife": 16000,
}
_ACTIVITY_DAILY_RATE: dict[str, float] = {
    "beach": 6000,
    "nature": 5000,
    "culture": 4000,
    "adventure": 9000,
    "wildlife": 11000,
    "citylife": 5000,
}
_DEFAULT_ACCOMMODATION_DAILY_RATE = 14000
_DEFAULT_ACTIVITY_DAILY_RATE = 6000

_FOOD_DAILY_RATE = 5000
_TRANSPORT_PER_DESTINATION = 8000
_DEFAULT_TRANSPORT_BASELINE = 15000  # used if no candidate destinations were found


def _category_from_interests(interests: list[str]) -> str | None:
    """Mirrors destination_agent's category derivation; kept local/self-contained."""
    if not interests:
        return None
    first = str(interests[0]).strip().replace(" ", "").lower()
    return first if first in _ACCOMMODATION_DAILY_RATE else None


def _estimate_cost(days: int, category: str | None, destination_count: int) -> dict[str, float]:
    accommodation_rate = _ACCOMMODATION_DAILY_RATE.get(category, _DEFAULT_ACCOMMODATION_DAILY_RATE)
    activity_rate = _ACTIVITY_DAILY_RATE.get(category, _DEFAULT_ACTIVITY_DAILY_RATE)

    nights = max(days - 1, 1)
    accommodation = accommodation_rate * nights
    activities = activity_rate * days
    food = _FOOD_DAILY_RATE * days
    transport = (
        _TRANSPORT_PER_DESTINATION * destination_count
        if destination_count > 0
        else _DEFAULT_TRANSPORT_BASELINE
    )

    return {
        "accommodation": accommodation,
        "activities": activities,
        "transport": transport,
        "food": food,
    }


def budget_availability_node(state: dict[str, Any]) -> dict[str, Any]:
    """LangGraph node: deterministically estimate cost and flag budget overruns.

    Reads:  days, budget, interests, candidate_destinations, plan.
    Writes: budget_breakdown (dict), plan (note appended).
    """
    try:
        days = max(int(state.get("days", 0) or 0), 1)
        budget = float(state.get("budget", 0) or 0)
        interests = list(state.get("interests", []) or [])
        destinations = list(state.get("candidate_destinations", []) or [])

        category = _category_from_interests(interests)
        breakdown = _estimate_cost(days, category, len(destinations))

        total = sum(breakdown.values())
        remaining = budget - total if budget > 0 else None
        over_budget = bool(budget > 0 and total > budget)

        result = {
            **breakdown,
            "total": total,
            "remaining": remaining,
            "over_budget": over_budget,
        }
    except Exception as exc:  # unexpected type errors, bad state shape, etc.
        logger.warning(
            "budget_availability_node: estimation failed (%s: %s) — returning zero-cost stub",
            type(exc).__name__,
            exc,
        )
        result = {
            "accommodation": 0, "activities": 0, "transport": 0, "food": 0,
            "total": 0, "remaining": None, "over_budget": False,
        }

    if result["remaining"] is not None:
        if result["over_budget"]:
            note = (
                f"Estimated cost: LKR {result['total']:,.0f} — exceeds your budget of "
                f"LKR {state.get('budget', 0):,.0f} by LKR {abs(result['remaining']):,.0f}."
            )
        else:
            note = (
                f"Estimated cost: LKR {result['total']:,.0f}, within your budget of "
                f"LKR {state.get('budget', 0):,.0f} (LKR {result['remaining']:,.0f} remaining)."
            )
    else:
        note = f"Estimated cost: LKR {result['total']:,.0f}. No budget was provided to compare against."

    plan = state.get("plan", "")
    updated_plan = f"{plan}\n\n{note}" if plan else note

    return {
        "budget_breakdown": result,
        "plan": updated_plan,
    }
