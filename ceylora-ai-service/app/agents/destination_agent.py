"""Destination agent — second node in the chain, and the first real tool call.

Unlike the planner (which asks an LLM), this node calls the CEYLORA .NET API's
internal service-to-service endpoint and pulls REAL destination rows from
Postgres. Destination names stay grounded in the actual catalog instead of
whatever an LLM might invent.

Same safety contract as planner_agent: any failure (API down, timeout, 401,
bad JSON, empty catalog, missing config) is caught, logged, and degraded
gracefully — the graph never crashes.
"""

from __future__ import annotations

import logging
import os
from typing import Any

import requests
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger("ceylora.agents.destination")

# Mirrors CEYLORA.Domain.Entities.TravelCategory — used to turn a free-text
# interest tag into a category filter the internal endpoint understands.
_TRAVEL_CATEGORIES = {"beach", "nature", "culture", "adventure", "wildlife", "citylife"}

_HTTP_TIMEOUT = 10  # seconds


def _category_from_interests(interests: list[str]) -> str | None:
    """Map the first interest to a TravelCategory name, if it matches one."""
    if not interests:
        return None
    first = str(interests[0]).strip().replace(" ", "").lower()
    return first if first in _TRAVEL_CATEGORIES else None


def _fetch_destinations(category: str | None) -> list[dict[str, Any]]:
    """GET the internal destinations endpoint. Raises on any HTTP/transport/config error."""
    base_url = os.environ.get("DOTNET_API_BASE_URL")
    api_key = os.environ.get("DOTNET_INTERNAL_API_KEY")
    if not base_url or not api_key:
        raise RuntimeError("DOTNET_API_BASE_URL or DOTNET_INTERNAL_API_KEY is not set")

    params = {"category": category} if category else {}
    response = requests.get(
        f"{base_url.rstrip('/')}/api/internal/destinations",
        headers={"X-Internal-Api-Key": api_key},
        params=params,
        timeout=_HTTP_TIMEOUT,
    )
    response.raise_for_status()  # 401 / 5xx / etc. -> HTTPError

    data = response.json()
    if not isinstance(data, list):
        raise RuntimeError(f"Unexpected response shape: {type(data).__name__}")
    return data


def destination_node(state: dict[str, Any]) -> dict[str, Any]:
    """LangGraph node: pull real candidate destinations from the .NET catalog.

    Reads:  interests (optional), plan (to append a note).
    Writes: candidate_destinations (list of dicts), plan (note appended).
    """
    interests = list(state.get("interests", []) or [])
    category = _category_from_interests(interests)

    try:
        destinations = _fetch_destinations(category)
    except Exception as exc:  # API down, timeout, 401, bad JSON, missing config, ...
        logger.warning(
            "destination_node: catalog lookup failed (%s: %s) — continuing with no candidates",
            type(exc).__name__,
            exc,
        )
        destinations = []

    names = [d.get("name", "") for d in destinations if d.get("name")]

    if names:
        note = "Suggested destinations from our catalog: " + ", ".join(names) + "."
    else:
        note = "No matching destinations found in catalog."

    plan = state.get("plan", "")
    updated_plan = f"{plan}\n\n{note}" if plan else note

    return {
        "candidate_destinations": destinations,
        "plan": updated_plan,
    }
