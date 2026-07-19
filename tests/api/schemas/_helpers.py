"""Test-side helpers that wrap pydantic validation for clean failure messages.

These wrap the raw `Model.model_validate(...)` call so test failures show
the actual offending payload + which field drifted, rather than a bare
``pydantic.ValidationError`` traceback.
"""

from __future__ import annotations

import httpx
import pytest
from pydantic import BaseModel, ValidationError

from .base import PaginatedEnvelope, ShowEnvelope


def validate_index_response[ItemT: BaseModel](
    response: httpx.Response,
    item_model: type[ItemT],
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


def validate_show_response[ItemT: BaseModel](
    response: httpx.Response,
    model: type[ItemT],
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


def assert_create_round_trip[ItemT: BaseModel](
    client: httpx.Client,
    path: str,
    payload: dict,
    param_key: str,
    show_model: type[ItemT],
    *,
    ignore_fields: set[str] | None = None,
    identifier: str = "slug",
) -> ShowEnvelope[ItemT]:
    """Create a resource, fetch it via Show, assert every field in the
    request payload survived persistence.

    Catches two classes of drift the schema layer alone misses:

    - **Persistence bugs:** the client sends ``description: "foo"`` and
      the model never persists it (silent drop, mass-assignment guard,
      etc.). Show response would omit it or return something else.
    - **Show-endpoint bugs:** the value is persisted (you can see it in
      Rails console) but the Show serializer omits it from the response.

    Args:
        identifier: which field of the create response to use as the
            show-URL segment. Documents use ``"slug"`` (default);
            ControlCatalog / ControlMapping / BackMatterResource /
            FederationPeer use ``"id"``.
        ignore_fields: payload fields the show response is NOT expected
            to mirror (e.g. ``service_token`` and ``signing_secret`` on
            federation peers — the API exposes only ``*_set`` booleans).
            Server-managed fields like timestamps, ids, slugs, derived
            counts also belong here if the payload happens to set them.

    The created resource is deleted in a ``finally`` block so the
    helper is safe to use without an explicit fixture.
    """
    ignore_fields = ignore_fields or set()

    create_response = client.post(path, json=payload)
    assert create_response.status_code in (200, 201), create_response.text
    created = create_response.json()["data"]
    resource_id = created[identifier]

    try:
        show_response = client.get(f"{path}/{resource_id}")
        envelope = validate_show_response(show_response, show_model)
        shown = envelope.data.model_dump(mode="json")

        sent = payload.get(param_key, payload)  # peers/back-matter don't wrap
        mismatches = []
        for field, expected in sent.items():
            if field in ignore_fields:
                continue
            if field not in shown:
                mismatches.append(
                    f"  - {field!r}: sent {expected!r}, not present in show response"
                )
            elif shown[field] != expected:
                mismatches.append(
                    f"  - {field!r}: sent {expected!r}, shown {shown[field]!r}"
                )

        if mismatches:
            pytest.fail(
                f"Round-trip drift at {path}/{resource_id} "
                f"(create payload → show response):\n" + "\n".join(mismatches)
            )

        return envelope
    finally:
        # Best-effort cleanup; ignore 404 if a destroy test ran concurrently.
        client.delete(f"{path}/{resource_id}")


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
