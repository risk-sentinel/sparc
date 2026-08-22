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

# Raw subject sets, then the parametrized wrappers derived from them. The raw
# lists are what the census and the probing tests iterate; keeping both from one
# definition is what stops the two disagreeing about what is covered.
WRITE_ENDPOINTS = [e for e in ENDPOINTS if e.is_write]
BODY_WRITE_ENDPOINTS = [e for e in WRITE_ENDPOINTS if _id(e) not in BODYLESS_WRITES]
ID_BEARING_ENDPOINTS = [e for e in ENDPOINTS if ":" in e.template]
COLLECTION_READ_ENDPOINTS = [
    e for e in ENDPOINTS if e.method == "GET" and ":" not in e.template
]

ALL = [pytest.param(e, id=_id(e)) for e in ENDPOINTS]
WRITES = [pytest.param(e, id=_id(e)) for e in WRITE_ENDPOINTS]
BODY_WRITES = [pytest.param(e, id=_id(e)) for e in BODY_WRITE_ENDPOINTS]


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
COLLECTION_READS = [pytest.param(e, id=_id(e)) for e in COLLECTION_READ_ENDPOINTS]


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
def test_every_list_endpoint_returns_the_documented_envelope(
    admin_client: httpx.Client
) -> None:
    """Matrix read-check 1, over every collection read that actually lists.

    Written as ONE test that probes and reports, rather than as a parametrized
    case per endpoint that skips when the endpoint turns out not to be a
    listing. A per-case skip is indistinguishable from a per-case pass in the
    summary line, and "70 skipped" answers nothing about what was checked — the
    skip happened because the check was written to skip, which is circular.

    Here the subjects are DISCOVERED and counted. Every endpoint that returns a
    list is asserted, every endpoint that does not is named as excluded, and the
    census below pins the numbers so silent erosion fails.
    """
    listed, not_listings, offenders = [], [], []

    for endpoint in COLLECTION_READ_ENDPOINTS:
        if _id(endpoint) in DOCUMENTED_ENVELOPE_DIVERGENCES:
            not_listings.append((_id(endpoint), "documented divergence"))
            continue

        response = admin_client.get(endpoint.path)
        if response.status_code != 200:
            not_listings.append((_id(endpoint), f"answered {response.status_code}"))
            continue

        body = response.json()
        if not isinstance(body, dict) or not isinstance(body.get("data"), list):
            not_listings.append((_id(endpoint), "does not return a list"))
            continue

        listed.append(_id(endpoint))
        meta = body.get("meta")
        if not isinstance(meta, dict):
            offenders.append(f"{_id(endpoint)}: no `meta`")
            continue
        missing = {"page", "pages", "count", "items"} - set(meta)
        if missing:
            offenders.append(f"{_id(endpoint)}: `meta` missing {sorted(missing)} — got {meta}")

    assert not offenders, "list endpoints not publishing the standard envelope:\n" + "\n".join(
        f"  {o}" for o in offenders
    )

    # A check that asserts nothing passes silently, so the subject count is
    # itself asserted. If a refactor stops these from listing, this fails.
    assert len(listed) >= 20, (
        f"only {len(listed)} endpoints returned a list, which is too few for this "
        f"check to mean anything. Excluded: {not_listings}"
    )


@pytest.mark.validation
@pytest.mark.parametrize("endpoint", ALL)
def test_every_refusal_is_a_json_error_envelope(
    admin_client: httpx.Client, endpoint: Endpoint
) -> None:
    """Whatever an endpoint refuses with, it refuses in JSON naming the reason.

    This replaced a 404-only version that skipped whenever the answer was not a
    404 — 64 of 310 cases, which made the check's own coverage unreadable. Any
    non-2xx qualifies now, so nothing skips and 400/404/422/502 are all covered
    rather than just one of them.

    This is the shape ActionController::ParameterMissing used to break: a JSON
    API rendering Rails' HTML error page.
    """
    response = admin_client.request(endpoint.method, endpoint.path)
    if 200 <= response.status_code < 300:
        return  # success is checked elsewhere; this is about refusals

    content_type = response.headers.get("content-type", "")
    assert content_type.startswith("application/json"), (
        f"{endpoint} refused with {response.status_code} and content-type "
        f"{content_type!r}: {response.text[:160]}"
    )

    body = response.json()
    assert isinstance(body, dict) and body.get("error"), (
        f"{endpoint} refused with {response.status_code} and no `error` key: "
        f"{response.text[:200]}"
    )


# Endpoints whose path carries a parameter, so an unresolvable value names a
# record that cannot exist.
ID_BEARING = [pytest.param(e, id=_id(e)) for e in ID_BEARING_ENDPOINTS]


@pytest.mark.validation
@pytest.mark.parametrize("endpoint", ID_BEARING)
def test_no_id_bearing_endpoint_succeeds_for_a_record_that_cannot_exist(
    admin_client: httpx.Client, endpoint: Endpoint
) -> None:
    """A 2xx for an unresolvable id means the endpoint found something absent.

    This exists because the 404-envelope check above SKIPS whenever the answer
    is not a 404 — which is correct for a collection with no id to miss, but
    would also skip silently past an endpoint that answered 200 for a record
    that does not exist. A conditional skip that can hide the very thing it
    should catch is the #984 shape, so the condition is asserted here instead
    of being left to whoever reads the skip list.

    404, 401, 403, 400 and 422 are all fine. Only success is not.
    """
    response = admin_client.request(endpoint.method, endpoint.path)

    assert not (200 <= response.status_code < 300), (
        f"{endpoint} answered {response.status_code} for an id that cannot resolve "
        f"({endpoint.path}): {response.text[:200]}"
    )


def test_the_sweep_census(admin_client: httpx.Client) -> None:
    """What this file actually asserts, pinned as numbers.

    A sweep's credibility is its subject count, and a subject count that lives
    only in a summary line can shrink without anyone noticing — a check that
    silently starts covering nothing still reports green. So the counts are
    asserted here, and a change to the surface has to come through this test.

    Reported by `-s` so the numbers are legible in a run, not just enforced.
    """
    total = len(ENDPOINTS)
    writes = sum(1 for e in ENDPOINTS if e.is_write)
    reads = total - writes
    body_writes = len(BODY_WRITE_ENDPOINTS)
    id_bearing = len(ID_BEARING_ENDPOINTS)
    collection_reads = len(COLLECTION_READ_ENDPOINTS)

    census = {
        "endpoints on the surface": total,
        "  writes": writes,
        "  reads": reads,
        "refuses anonymous": total,
        "refuses a bad token": total,
        "no 5xx": total,
        "refuses an unparseable body": body_writes,
        "no 2xx for an unresolvable id": id_bearing,
        "refusals are JSON envelopes": total,
        "collection reads probed for the list envelope": collection_reads,
    }
    print("\n  sweep census")
    for label, count in census.items():
        print(f"    {label:48} {count:4}")
    print(f"    {'TOTAL per-endpoint assertions':48} "
          f"{total * 4 + body_writes + id_bearing:4}")

    # The surface only grows in practice; a drop means the snapshot lost
    # entries, which is the drift guard's business but worth failing here too.
    assert total >= 310, f"the surface shrank to {total} entries"
    assert writes >= 200, f"only {writes} write endpoints — did the snapshot lose entries?"
    assert id_bearing >= 240, f"only {id_bearing} id-bearing endpoints"
    assert collection_reads >= 25, f"only {collection_reads} collection reads"
    assert body_writes == writes - len(BODYLESS_WRITES), (
        "the bodyless-write exclusion list and the write count disagree"
    )
