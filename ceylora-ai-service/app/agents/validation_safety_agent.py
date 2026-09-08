"""Validation & Safety agent — fourth and final node in the chain.

Applies deterministic checks against the accumulated state (not another LLM
call) and produces a PASS/NEEDS_REVISION verdict per rule, plus an overall
`requires_approval` flag. This is the gate the human-approval step in the
.NET backend will read before letting a workflow auto-confirm.

Also does a lightweight prompt-injection check on the free-text `goal`:
if suspicious phrasing is detected, it's logged and flagged in the results,
but it never changes the actual approval outcome — approval stays a backend
business rule, never something the AI can grant itself.
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger("ceylora.agents.validation_safety")

_MAX_REASONABLE_DAYS = 30
_APPROVAL_THRESHOLD_LKR = 100_000

_INJECTION_MARKERS = (
    "ignore previous", "ignore all", "bypass approval", "auto-approve",
    "skip approval", "override", "approve automatically", "disregard the rules",
)


def _check_dates(days: int) -> dict[str, Any]:
    if days <= 0:
        return {"rule": "duration", "status": "FAIL", "message": "Trip duration must be at least 1 day."}
    if days > _MAX_REASONABLE_DAYS:
        return {"rule": "duration", "status": "FAIL", "message": f"Trip duration of {days} days exceeds the {_MAX_REASONABLE_DAYS}-day planning limit."}
    return {"rule": "duration", "status": "PASS", "message": f"Duration of {days} day(s) is within range."}


def _check_budget(budget_breakdown: dict[str, Any]) -> dict[str, Any]:
    if not budget_breakdown:
        return {"rule": "budget", "status": "FAIL", "message": "No budget estimate was produced."}
    if budget_breakdown.get("over_budget"):
        return {"rule": "budget", "status": "FAIL", "message": "Estimated cost exceeds the traveler's stated budget."}
    return {"rule": "budget", "status": "PASS", "message": "Estimated cost is within budget."}


def _check_destinations(candidates: list[dict[str, Any]]) -> dict[str, Any]:
    if not candidates:
        return {"rule": "destinations", "status": "FAIL", "message": "No matching destinations were found in the catalog."}
    return {"rule": "destinations", "status": "PASS", "message": f"{len(candidates)} candidate destination(s) found."}


def _check_prompt_injection(goal: str) -> dict[str, Any]:
    lowered = (goal or "").lower()
    hit = next((marker for marker in _INJECTION_MARKERS if marker in lowered), None)
    if hit:
        logger.warning("validation_safety_node: suspicious phrasing detected in goal: %r", hit)
        return {
            "rule": "prompt_injection",
            "status": "FLAGGED",
            "message": "Suspicious instruction-like phrasing detected in the traveler's request; ignored. Approval rules are enforced by the backend regardless of request wording.",
        }
    return {"rule": "prompt_injection", "status": "PASS", "message": "No suspicious phrasing detected."}


def _requires_approval(results: list[dict[str, Any]], budget_breakdown: dict[str, Any]) -> bool:
    if any(r["status"] == "FAIL" for r in results):
        return True
    total = budget_breakdown.get("total", 0) or 0
    return bool(total >= _APPROVAL_THRESHOLD_LKR)


def validation_safety_node(state: dict[str, Any]) -> dict[str, Any]:
    """LangGraph node: run deterministic checks and decide if approval is required.

    Reads:  days, goal, candidate_destinations, budget_breakdown, plan.
    Writes: validation_results (list), overall_status, requires_approval, plan (note appended).
    """
    try:
        days = int(state.get("days", 0) or 0)
        goal = str(state.get("goal", "") or "")
        candidates = list(state.get("candidate_destinations", []) or [])
        budget_breakdown = dict(state.get("budget_breakdown", {}) or {})

        results = [
            _check_dates(days),
            _check_budget(budget_breakdown),
            _check_destinations(candidates),
            _check_prompt_injection(goal),
        ]

        hard_failed = any(r["status"] == "FAIL" for r in results)
        overall_status = "NEEDS_REVISION" if hard_failed else "PASS"
        requires_approval = _requires_approval(results, budget_breakdown)

    except Exception as exc:  # any unexpected shape/type error -> safe failure, not a crash
        logger.warning(
            "validation_safety_node: validation failed unexpectedly (%s: %s) — defaulting to safe failure",
            type(exc).__name__,
            exc,
        )
        results = [{"rule": "internal", "status": "FAIL", "message": "Validation could not be completed."}]
        overall_status = "NEEDS_REVISION"
        requires_approval = True  # safe default: never silently auto-confirm on error

    failed_rules = [r["message"] for r in results if r["status"] == "FAIL"]
    if overall_status == "PASS":
        note = "Validation passed all checks." + (
            " Requires operator approval before confirmation (cost threshold)." if requires_approval else ""
        )
    else:
        note = "Validation flagged issues: " + " ".join(failed_rules)

    plan = state.get("plan", "")
    updated_plan = f"{plan}\n\n{note}" if plan else note

    return {
        "validation_results": results,
        "overall_status": overall_status,
        "requires_approval": requires_approval,
        "plan": updated_plan,
    }
