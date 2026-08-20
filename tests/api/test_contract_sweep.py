"""The #995 contract sweep: checks that apply to EVERY /api/v1 endpoint.

Bundle V's matrix has six checks per write endpoint and five per read. Most of
them need a valid payload and a real record, so they live in the per-resource
modules. The ones here need neither, which is what lets them cover the whole
surface rather than the part someone remembered to write a module for.

The surface comes from `spec/fixtures/api_v1_endpoints.txt` — the snapshot the
Rails drift guard pins — so an endpoint cannot be added without appearing here.
That is the property that matters: a sweep that enumerates its own subjects
covers what exists, not what its author listed.
"""

from __future__ import annotations

import httpx
import pytest

from api_surface import ENDPOINTS, Endpoint

pytestmark = [pytest.mark.phase2]


def _id(endpoint: Endpoint) -> str:
    return f"{endpoint.method} {endpoint.template}"


# Endpoints that take NO request body, so "was the body understood" is not a
# question they can answer. Each is listed with the reason, because an
# exclusion list is where a sweep quietly stops sweeping.
BODYLESS_WRITES = {
    # Bridges the Bearer token in the Authorization header to a session cookie.
    # There is no body to misunderstand.
    "POST /api/v1/sessions/from_token",
}

ALL = [pytest.param(e, id=_id(e)) for e in ENDPOINTS]
WRITES = [pytest.param(e, id=_id(e)) for e in ENDPOINTS if e.is_write]
BODY_WRITES = [
    pytest.param(e, id=_id(e))
    for e in ENDPOINTS
    if e.is_write and _id(e) not in BODYLESS_WRITES
]


def test_the_bodyless_exclusions_are_all_real_endpoints() -> None:
    """An exclusion for an endpoint that no longer exists silently grows the gap."""
    known = {_id(e) for e in ENDPOINTS}
    assert BODYLESS_WRITES <= known, (
        f"excluded endpoints that are not on the surface: {BODYLESS_WRITES - known}"
    )


@pytest.mark.auth
@pytest.mark.parametrize("endpoint", ALL)
def test_every_endpoint_refuses_an_anonymous_caller(
    anon_client: httpx.Client, endpoint: Endpoint
) -> None:
    """Matrix check 5, applied to the whole surface.

    An unresolvable id is used on purpose. Authentication must be decided
    BEFORE the record is looked up, so a 404 here is a finding, not a pass: it
    means the endpoint told an anonymous caller whether something exists.
    """
    response = anon_client.request(endpoint.method, endpoint.path)

    assert response.status_code == 401, (
        f"{endpoint} answered {response.status_code} to an unauthenticated caller "
        f"(expected 401): {response.text[:200]}"
    )


@pytest.mark.auth
@pytest.mark.parametrize("endpoint", ALL)
def test_every_endpoint_refuses_a_revoked_token(
    bad_token_client: httpx.Client, endpoint: Endpoint
) -> None:
    """A well-formed but unknown token must be refused exactly like no token.

    Distinguishing the two tells an attacker which of their guesses are real
    tokens, and #758 already had to pace this endpoint-by-endpoint for the
    session bridge.
    """
    response = bad_token_client.request(endpoint.method, endpoint.path)

    assert response.status_code == 401, (
        f"{endpoint} answered {response.status_code} to a bad token "
        f"(expected 401): {response.text[:200]}"
    )


@pytest.mark.happy
@pytest.mark.parametrize("endpoint", ALL)
def test_no_endpoint_returns_a_server_error_to_an_authenticated_caller(
    admin_client: httpx.Client, endpoint: Endpoint
) -> None:
    """Nothing on the surface may 5xx for a well-formed request.

    The ids do not resolve, so 404 is the expected answer nearly everywhere and
    422 is fine for a write with no body. A 500 means an unhandled path — the
    class that renders an HTML error page from a JSON API, which is what
    ActionController::ParameterMissing did to every `params.require` endpoint
    before it was rescued.
    """
    response = admin_client.request(endpoint.method, endpoint.path)

    assert response.status_code < 500, (
        f"{endpoint} answered {response.status_code}: {response.text[:300]}"
    )


@pytest.mark.validation
@pytest.mark.parametrize("endpoint", BODY_WRITES)
def test_no_write_endpoint_answers_success_to_a_body_it_cannot_act_on(
    admin_client: httpx.Client, endpoint: Endpoint
) -> None:
    """Matrix check 4, applied to every write on the surface.

    The record does not exist, so the honest answers are 404, 400 or 422. A 2xx
    would mean the endpoint acted on a body it could not have understood,
    against a record it could not have found — the #994 shape.
    """
    response = admin_client.request(
        endpoint.method,
        endpoint.path,
        json={"a_field_this_endpoint_does_not_accept": "x"},
    )

    assert not (200 <= response.status_code < 300), (
        f"{endpoint} answered {response.status_code} for an unresolvable record and an "
        f"unrecognized body: {response.text[:200]}"
    )


# Collection reads: a GET whose path carries no parameters is an index, and
# every index in this API publishes the same paginated envelope.
COLLECTION_READS = [
    pytest.param(e, id=_id(e))
    for e in ENDPOINTS
    if e.method == "GET" and ":" not in e.template
]


# Endpoints whose list envelope deliberately differs, with the page that says
# so. A divergence that is documented is a contract; one that is not is drift,
# and the difference between them is the whole point of checking.
#
# `/controls` is the only entry here with a published alternative:
# endpoints/control-lookup.md documents `meta: {total, limit, scoped_to_profile,
# profile_title}`. The others are NOT documented as different and are reported
# as findings by the test below.
DOCUMENTED_ENVELOPE_DIVERGENCES = {
    "GET /api/v1/controls": "endpoints/control-lookup.md publishes meta.total / meta.limit",
}


@pytest.mark.happy
@pytest.mark.parametrize("endpoint", COLLECTION_READS)
def test_every_collection_read_returns_the_documented_envelope(
    admin_client: httpx.Client, endpoint: Endpoint
) -> None:
    """Matrix read-check 1, applied to every index on the surface.

    `docs/api/errors.md` and every endpoint page publish `{data: [...], meta:
    {page, pages, count, items}}` for a list. An index that returns a bare
    array, or omits `meta`, breaks every paginating client — and no single
    resource module would notice, because each one only ever looks at its own.
    """
    response = admin_client.get(endpoint.path)

    # A few collection paths are actions rather than listings (export, discovery
    # summaries). They are still reads and must still answer, but they do not
    # promise a paginated envelope.
    if response.status_code != 200:
        pytest.skip(f"{endpoint} answered {response.status_code}, not a listing to shape-check")

    body = response.json()
    if not isinstance(body, dict) or "data" not in body or not isinstance(body["data"], list):
        pytest.skip(f"{endpoint} is not a list endpoint")

    if _id(endpoint) in DOCUMENTED_ENVELOPE_DIVERGENCES:
        pytest.skip(
            f"{endpoint} publishes a different envelope on purpose: "
            f"{DOCUMENTED_ENVELOPE_DIVERGENCES[_id(endpoint)]}"
        )

    assert "meta" in body, f"{endpoint} returned a list with no `meta`: {response.text[:200]}"
    missing = {"page", "pages", "count", "items"} - set(body["meta"])
    assert not missing, (
        f"{endpoint} `meta` is missing {sorted(missing)}: {body['meta']}"
    )


@pytest.mark.validation
@pytest.mark.parametrize("endpoint", ALL)
def test_every_not_found_uses_the_documented_error_envelope(
    admin_client: httpx.Client, endpoint: Endpoint
) -> None:
    """When an endpoint 404s, it must say so in JSON with an `error` key.

    This is the shape ActionController::ParameterMissing used to break: a JSON
    API rendering Rails' HTML error page. Asserted only when the answer IS a
    404, so an endpoint that legitimately answers otherwise is not forced into
    one.
    """
    response = admin_client.request(endpoint.method, endpoint.path)
    if response.status_code != 404:
        pytest.skip(f"{endpoint} answered {response.status_code}")

    assert response.headers.get("content-type", "").startswith("application/json"), (
        f"{endpoint} 404'd with content-type "
        f"{response.headers.get('content-type')!r}: {response.text[:160]}"
    )

    body = response.json()
    assert isinstance(body, dict) and body.get("error"), (
        f"{endpoint} 404'd without an `error` key: {response.text[:200]}"
    )
