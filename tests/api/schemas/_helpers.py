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


def _read_back(
    client: httpx.Client,
    url: str,
    show_model: type[BaseModel] | None,
) -> tuple[dict, object]:
    """Independent GET of a resource, as a plain dict plus whatever the caller
    should get back.

    ``show_model`` is optional because only about half the API surface has a
    pydantic model here, and the round-trip check is worth having on the half
    that does not. With a model the response envelope is validated too; without
    one the read still happens and the fields are still compared — it just
    proves less about the response's shape.
    """
    response = client.get(url)
    if show_model is not None:
        envelope = validate_show_response(response, show_model)
        return envelope.data.model_dump(mode="json"), envelope

    assert response.status_code == 200, response.text
    body = response.json()
    data = body.get("data", body) if isinstance(body, dict) else body
    return data, data


def assert_update_round_trip[ItemT: BaseModel](
    client: httpx.Client,
    path: str,
    resource_id: str | int,
    changes: dict,
    param_key: str,
    show_model: type[ItemT] | None = None,
    *,
    method: str = "patch",
    ignore_fields: set[str] | None = None,
    restore: bool = True,
) -> ShowEnvelope[ItemT] | dict:
    """Update a resource, fetch it back with an INDEPENDENT read, assert every
    changed field actually persisted, then restore the original values.

    This is the update-side counterpart of ``assert_create_round_trip``, and it
    exists because eight update tests in this suite assert a status code and
    never read the response body — every one of which would pass against an
    endpoint that discarded the payload entirely. That is not hypothetical:
    #994's ``PUT .../parameters`` answered ``200 {"status": "updated"}`` to a
    body it never parsed, with a green suite throughout.

    Three things are asserted, in this order:

    1. **The change is a real change.** Each field in ``changes`` is compared
       against the resource's current value first, and the helper fails if they
       already match. Asserting that a field equals a value it already held
       proves nothing about the write, and the failure mode is invisible — the
       test passes forever while covering nothing.
    2. **The write reports success.**
    3. **An independent GET shows the new value.** Not the write's own echo,
       which can be synthesised from the request without anything being
       persisted.

    Args:
        resource_id: the show-URL segment — slug, id or canonical identifier,
            whichever the endpoint addresses resources by.
        changes: the fields to set, unwrapped. Wrapped in ``param_key`` for the
            request when that is how the endpoint accepts them.
        method: ``"patch"`` (default) or ``"put"``.
        ignore_fields: fields sent but not expected to be mirrored back, e.g.
            write-only credentials the API reports only as ``*_set`` booleans.
        restore: put the original values back afterwards. Leave on unless the
            caller owns a throwaway resource it deletes itself.
    """
    ignore_fields = ignore_fields or set()

    original, _ = _read_back(client, f"{path}/{resource_id}", show_model)

    no_ops = [
        f"  - {field!r}: already {original[field]!r} before the update"
        for field, value in changes.items()
        if field not in ignore_fields and field in original and original[field] == value
    ]
    if no_ops:
        pytest.fail(
            f"Vacuous update at {path}/{resource_id} — these fields already held the "
            f"value the test sets, so the round trip would pass without the endpoint "
            f"writing anything:\n" + "\n".join(no_ops)
        )

    body = {param_key: changes} if param_key else changes
    write = getattr(client, method)(f"{path}/{resource_id}", json=body)
    assert write.status_code in (200, 201, 202), write.text

    try:
        shown, after = _read_back(client, f"{path}/{resource_id}", show_model)

        mismatches = []
        for field, expected in changes.items():
            if field in ignore_fields:
                continue
            if field not in shown:
                mismatches.append(
                    f"  - {field!r}: sent {expected!r}, not present in show response"
                )
            elif shown[field] != expected:
                mismatches.append(
                    f"  - {field!r}: sent {expected!r}, shown {shown[field]!r} "
                    f"(was {original.get(field)!r} before the update)"
                )

        if mismatches:
            pytest.fail(
                f"Update round-trip drift at {path}/{resource_id} — the write returned "
                f"{write.status_code} but an independent read disagrees:\n"
                + "\n".join(mismatches)
            )

        return after
    finally:
        if restore:
            restore_body = {f: original.get(f) for f in changes if f not in ignore_fields}
            getattr(client, method)(
                f"{path}/{resource_id}",
                json={param_key: restore_body} if param_key else restore_body,
            )


def assert_unhandled_payload_is_not_reported_as_success[ItemT: BaseModel](
    client: httpx.Client,
    path: str,
    resource_id: str | int,
    payload: dict,
    show_model: type[ItemT] | None = None,
    *,
    method: str = "patch",
) -> httpx.Response:
    """Send a payload the endpoint cannot act on and prove it does not answer
    as though it had.

    "Nothing to do" and "I did not understand you" must not share a response.
    Rails' ``params.permit`` drops what it does not recognise, so a controller
    reading the wrong key sees an empty set of changes and takes the success
    branch — the exact mechanism behind #994, and it is available to every
    controller in the codebase.

    The rule enforced here is narrow and checkable: if an independent read
    shows the resource is byte-identical afterwards, the response must not have
    been a 2xx. An endpoint that changed nothing is free to say so with a 4xx,
    and free to change something and report it; what it may not do is accept a
    payload, change nothing, and report success.

    Returns the write response so the caller can assert on the specific error
    shape its documentation publishes.
    """
    original, _ = _read_back(client, f"{path}/{resource_id}", show_model)

    write = getattr(client, method)(f"{path}/{resource_id}", json=payload)

    after = validate_show_response(client.get(f"{path}/{resource_id}"), show_model)
    shown = after.data.model_dump(mode="json")

    if shown == original and 200 <= write.status_code < 300:
        pytest.fail(
            f"{method.upper()} {path}/{resource_id} answered {write.status_code} "
            f"{write.text[:200]!r} to a payload it did not act on — an independent read "
            f"shows the resource is unchanged. This is the #994 shape: a wrong answer "
            f"carrying a right status. Refuse the payload, or report honestly that "
            f"nothing was written."
        )

    return write
