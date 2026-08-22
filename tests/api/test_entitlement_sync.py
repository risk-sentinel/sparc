"""Tests for /api/v1/entitlement_sync (#860).

The dry run the epic asks for before `authoritative` is switched on. The
property that matters most is that preview WRITES NOTHING, so the destructive
cases are asked for deliberately and then checked against reality.

api-inventory: covers entitlement_sync#show
api-inventory: covers entitlement_sync#preview
"""

from __future__ import annotations

import httpx
import pytest

pytestmark = [pytest.mark.admin, pytest.mark.phase2]

SHOW = "/api/v1/entitlement_sync"
PREVIEW = "/api/v1/entitlement_sync/preview"

MODES = ["off", "bootstrap", "authoritative"]


def _self_id(client: httpx.Client) -> int:
    resp = client.get("/api/v1/users", params={"items": 1})
    resp.raise_for_status()
    rows = resp.json()["data"]
    if not rows:
        pytest.skip("no users visible on this instance")
    return rows[0]["id"]


class TestShow:
    def test_reports_the_configuration(self, admin_client: httpx.Client) -> None:
        resp = admin_client.get(SHOW)

        assert resp.status_code == 200, resp.text
        data = resp.json()["data"]
        assert data["mode"] in MODES
        assert data["modes"] == MODES

    def test_reports_whether_the_groups_scope_was_requested(
        self, admin_client: httpx.Client
    ) -> None:
        # A scope is a request; the IdP decides what it releases. The commonest
        # support case is a correct claim name with the scope never asked for.
        data = admin_client.get(SHOW).json()["data"]

        assert isinstance(data["grants_scope_requested"], bool)
        assert data["grants_scope_requested"] == ("groups" in data["oidc_scopes"].split())

    def test_managed_counts_only_what_the_sync_owns(self, admin_client: httpx.Client) -> None:
        managed = admin_client.get(SHOW).json()["data"]["managed"]

        assert managed["user_roles"] >= 0
        assert managed["organization_memberships"] >= 0


class TestPreviewWritesNothing:
    def test_a_revoking_preview_does_not_revoke(self, admin_client: httpx.Client) -> None:
        # The dangerous question, asked safely: authoritative with an empty
        # claim is the maximum-revocation case.
        user_id = _self_id(admin_client)
        before = admin_client.get(SHOW).json()["data"]["managed"]

        resp = admin_client.post(
            PREVIEW, json={"preview": {"user_id": user_id, "mode": "authoritative", "grants": []}}
        )

        assert resp.status_code == 200, resp.text
        assert resp.json()["data"]["dry_run"] is True

        after = admin_client.get(SHOW).json()["data"]["managed"]
        assert after == before, "preview changed the managed membership counts"

    def test_an_adding_preview_does_not_add(self, admin_client: httpx.Client) -> None:
        user_id = _self_id(admin_client)
        before = admin_client.get(SHOW).json()["data"]["managed"]

        admin_client.post(
            PREVIEW,
            json={
                "preview": {
                    "user_id": user_id,
                    "mode": "bootstrap",
                    "grants": ["sparc:boundary:acme:acme-prod:isso"],
                }
            },
        )

        after = admin_client.get(SHOW).json()["data"]["managed"]
        assert after == before


class TestClaimPresence:
    def test_omitting_grants_is_not_the_same_as_sending_an_empty_list(
        self, admin_client: httpx.Client
    ) -> None:
        # Absent claim = misconfiguration, sync nothing. Empty claim = a real
        # statement. Collapsing them is how this feature de-provisions a tenant.
        user_id = _self_id(admin_client)

        absent = admin_client.post(
            PREVIEW, json={"preview": {"user_id": user_id, "mode": "authoritative"}}
        ).json()["data"]
        empty = admin_client.post(
            PREVIEW, json={"preview": {"user_id": user_id, "mode": "authoritative", "grants": []}}
        ).json()["data"]

        assert absent.get("error"), "an absent claim was not reported as an error"
        assert "not present in the token" in absent["error"]
        assert not empty.get("error"), "an empty claim was wrongly treated as absent"

    def test_an_absent_claim_plans_no_changes(self, admin_client: httpx.Client) -> None:
        user_id = _self_id(admin_client)

        data = admin_client.post(
            PREVIEW, json={"preview": {"user_id": user_id, "mode": "authoritative"}}
        ).json()["data"]

        assert data["changes"] == []


class TestUnresolvableGrants:
    def test_reports_the_reason_rather_than_creating_anything(
        self, admin_client: httpx.Client
    ) -> None:
        user_id = _self_id(admin_client)

        data = admin_client.post(
            PREVIEW,
            json={
                "preview": {
                    "user_id": user_id,
                    "mode": "bootstrap",
                    "grants": ["sparc:boundary:definitely-not-real:nor-this:isso"],
                }
            },
        ).json()["data"]

        assert data["unmatched"], "an unresolvable grant was not reported"
        assert "not found" in data["unmatched"][0]["reason"]
        assert data["changes"] == []


class TestRefusals:
    def test_unknown_mode_is_named_with_what_is_accepted(self, admin_client: httpx.Client) -> None:
        resp = admin_client.post(
            PREVIEW, json={"preview": {"user_id": _self_id(admin_client), "mode": "aggressive"}}
        )

        assert resp.status_code == 422, resp.text
        assert resp.json()["expected"] == MODES

    def test_unknown_user_is_404(self, admin_client: httpx.Client) -> None:
        resp = admin_client.post(PREVIEW, json={"preview": {"user_id": 999_999_999}})
        assert resp.status_code == 404


class TestAuthorization:
    def test_non_admin_is_refused_on_both(self, user_client: httpx.Client) -> None:
        assert user_client.get(SHOW).status_code == 403
        assert user_client.post(PREVIEW, json={"preview": {"user_id": 1}}).status_code == 403

    def test_anonymous_is_unauthorized_on_both(self, anon_client: httpx.Client) -> None:
        assert anon_client.get(SHOW).status_code == 401
        assert anon_client.post(PREVIEW, json={"preview": {"user_id": 1}}).status_code == 401
