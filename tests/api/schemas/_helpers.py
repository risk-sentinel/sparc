"""Test-side helpers that wrap pydantic validation for clean failure messages.

These wrap the raw `Model.model_validate(...)` call so test failures show
the actual offending payload + which field drifted, rather than a bare
``pydantic.ValidationError`` traceback.
"""

from __future__ import annotations

import json
from typing import Type, TypeVar

import httpx
import pytest
from pydantic import BaseModel, ValidationError

from .base import PaginatedEnvelope, ShowEnvelope

ItemT = TypeVar("ItemT", bound=BaseModel)


def validate_index_response(
    response: httpx.Response,
    item_model: Type[ItemT],
) -> PaginatedEnvelope[ItemT]:
    """Assert that ``response`` is a paginated list of ``item_model`` rows.

    Returns the parsed envelope so the caller can drive further assertions
    on the data (e.g. ``envelope.data[0].name == "expected"``).

    Drift surfaces as a single ``pytest.fail`` with the field path, the
    bad value, and an excerpt of the offending payload — much more useful
    than the raw pydantic traceback.
    """
    assert response.status_code == 200, response.text
    try:
        return PaginatedEnvelope[item_model].model_validate(response.json())
    except ValidationError as exc:
        pytest.fail(_format_drift(exc, response, expected=item_model.__name__))


def validate_show_response(
    response: httpx.Response,
    model: Type[ItemT],
) -> ShowEnvelope[ItemT]:
    """Assert that ``response`` is `{data: <model>}`.

    Returns the parsed envelope. Same drift-failure formatting as
    ``validate_index_response``.
    """
    assert response.status_code == 200, response.text
    try:
        return ShowEnvelope[model].model_validate(response.json())
    except ValidationError as exc:
        pytest.fail(_format_drift(exc, response, expected=model.__name__))


def _format_drift(
    exc: ValidationError,
    response: httpx.Response,
    *,
    expected: str,
) -> str:
    """Human-readable failure message for a schema validation error.

    Shows the field path, error type, observed value, and the first
    ~500 chars of the response body. Truncates so a 1000-row list
    doesn't bury the diagnosis.
    """
    lines = [f"Response did not conform to {expected}:"]
    for err in exc.errors():
        loc = ".".join(str(p) for p in err["loc"])
        lines.append(f"  - {loc}: {err['msg']} (input={err.get('input')!r})")
    body_excerpt = response.text[:500]
    if len(response.text) > 500:
        body_excerpt += "...[truncated]"
    lines.append(f"\nResponse body: {body_excerpt}")
    return "\n".join(lines)
