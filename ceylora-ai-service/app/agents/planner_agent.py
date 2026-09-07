"""Planner agent — first real LLM-backed LangGraph node.

Pattern for the other three agents (Destination, Budget & Availability,
Validation & Safety) to copy:

  1. Build a prompt from the graph state.
  2. Call the LLM through the shared helper (`_call_gemini`).
  3. Write results back into state under this node's own keys.
  4. Wrap the whole thing in try/except: on ANY failure, fall back to a
     deterministic stub so a demo never hard-fails, and record that the
     fallback ran via `state["generated_by"]`.

Only the planner is wired into the graph for now — see app/graph/workflow.py.
"""

from __future__ import annotations

import logging
import os
from functools import lru_cache
from typing import Any

from dotenv import load_dotenv

# Load .env once at import so GEMINI_API_KEY is available. Safe to call
# repeatedly; python-dotenv no-ops if the file is missing.
load_dotenv()

logger = logging.getLogger("ceylora.agents.planner")

# Free-tier eligible, fast, and lenient on rate limits.
_MODEL = "gemini-2.5-flash"


@lru_cache(maxsize=1)
def _model():
    """Lazily configure the Gemini client and build the model handle.

    Cached so configuration happens once per process. Import is local so the
    service still boots (and the stub path still works) even if
    `google-generativeai` or the key situation is broken.
    """
    import google.generativeai as genai

    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is not set")

    genai.configure(api_key=api_key)
    return genai.GenerativeModel(_MODEL)


def _build_prompt(goal: str, days: int, budget: float, interests: list[str]) -> str:
    interest_line = ", ".join(interests) if interests else "no specific interests given"
    return (
        f"Plan a {days}-day trip in Sri Lanka.\n"
        f"Traveler's goal: {goal}\n"
        f"Total budget: LKR {budget:,.0f}\n"
        f"Interests: {interest_line}\n\n"
        "Produce a day-by-day draft itinerary. For each day give:\n"
        "  - the destination / town name(s)\n"
        "  - 2-4 rough activities\n"
        "Keep it concise plain text (no markdown tables, no JSON). "
        "One short paragraph or a few bullet lines per day is fine."
    )


def _call_gemini(prompt: str) -> str:
    """Single LLM round-trip. Raises on any API/SDK error — caller handles fallback."""
    response = _model().generate_content(prompt)
    text = (response.text or "").strip()
    if not text:
        raise RuntimeError("Gemini API returned no text content")
    return text


def _stub_itinerary(goal: str, days: int, budget: float, interests: list[str]) -> str:
    """Deterministic fallback itinerary — no LLM involved."""
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
    """LangGraph node: turn the trip request in `state` into `state['plan']`.

    Expects keys: goal, days, budget, and optionally interests.
    Returns a partial state update with `plan` and `generated_by`.
    """
    goal = state.get("goal", "Unspecified trip")
    days = int(state.get("days", 1))
    budget = float(state.get("budget", 0.0))
    interests = list(state.get("interests", []) or [])

    try:
        plan_text = _call_gemini(_build_prompt(goal, days, budget, interests))
        return {"plan": plan_text, "generated_by": "planner_agent (gemini)"}
    except Exception as exc:  # missing key, rate limit (429), timeout, blocked response, ...
        logger.warning(
            "planner_node: LLM call failed (%s: %s) — falling back to stub itinerary",
            type(exc).__name__,
            exc,
        )
        return {
            "plan": _stub_itinerary(goal, days, budget, interests),
            "generated_by": "planner_agent (stub-fallback)",
        }
