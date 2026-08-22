"""CDEF coverage analysis API (#904).

Derives a boundary's deployed service inventory from Terraform and reports which
Component Definitions it needs.

The tests that matter most here are the negative ones. A .tfstate carries
plaintext secrets, and the entire design rests on the upload being read and
dropped — so the fixtures below deliberately carry a fake secret in
``instances[].attributes``, and the suite asserts it comes back in nothing.
"""

# api-inventory: covers cdef_coverage#create_run
# api-inventory: covers cdef_coverage#show_run
# api-inventory: covers cdef_coverage#destroy_run

from __future__ import annotations

import io
import json
import uuid

# A value that exists nowhere else, so finding it anywhere is unambiguous.
FAKE_SECRET = f"tfstate-secret-{uuid.uuid4().hex}"
FAKE_ACCOUNT = "123456789012"


def _state_bytes(resource_types, mode="managed"):
    body = {
        "version": 4,
        "terraform_version": "1.9.5",
        "resources": [
            {
                "mode": mode,
                "type": rtype,
                "name": "example",
                "instances": [
                    {"attributes": {"password": FAKE_SECRET, "account_id": FAKE_ACCOUNT}}
                ],
            }
            for rtype in resource_types
        ],
    }
    return json.dumps(body).encode()


def _plan_bytes(changes):
    body = {
        "format_version": "1.2",
        "resource_changes": [
            {"mode": "managed", "type": rtype, "name": "example",
             "change": {"actions": actions, "after": {"secret": FAKE_SECRET}}}
            for rtype, actions in changes
        ],
    }
    return json.dumps(body).encode()


def _files(*payloads):
    return [("files[]", (name, io.BytesIO(data), "application/json")) for name, data in payloads]


class TestAnalyze:
    def test_maps_resources_to_services_and_verdicts(self, admin_client):
        resp = admin_client.post(
            "/api/v1/cdef_coverage/analyze",
            files=_files(
                ("prod.tfstate", _state_bytes(["aws_ecs_service", "aws_guardduty_detector"]))
            ),
        )
        assert resp.status_code == 200, resp.text
        data = resp.json()["data"]

        services = {f["service"]: f["verdict"] for f in data["findings"]}
        assert "ecs" in services
        assert "guardduty" in services
        assert set(services.values()) <= {"adopt", "keep_custom", "needs_custom", "stale_custom"}
        assert data["counts"]["needs_custom"] >= 0

    def test_ignores_data_sources(self, admin_client):
        resp = admin_client.post(
            "/api/v1/cdef_coverage/analyze",
            files=_files(("data.tfstate", _state_bytes(["aws_ecs_service"], mode="data"))),
        )
        assert resp.status_code == 200
        assert resp.json()["data"]["findings"] == []

    def test_combines_several_files_as_one_boundary(self, admin_client):
        resp = admin_client.post(
            "/api/v1/cdef_coverage/analyze",
            files=_files(("ecs.tfstate", _state_bytes(["aws_ecs_service"])),
                         ("config.tfstate", _state_bytes(["aws_config_rule"]))),
        )
        assert resp.status_code == 200
        data = resp.json()["data"]
        assert {f["service"] for f in data["findings"]} >= {"ecs", "config"}
        assert {s["filename"] for s in data["sources"]} == {"ecs.tfstate", "config.tfstate"}

    def test_plan_excludes_a_resource_only_being_destroyed(self, admin_client):
        resp = admin_client.post(
            "/api/v1/cdef_coverage/analyze",
            files=_files(("plan.json", _plan_bytes([("aws_s3_bucket", ["create"]),
                                                    ("aws_sqs_queue", ["delete"])]))),
        )
        assert resp.status_code == 200
        services = {f["service"] for f in resp.json()["data"]["findings"]}
        assert "s3" in services
        assert "sqs" not in services

    def test_plan_counts_a_replacement(self, admin_client):
        """["delete", "create"] is a replacement — the resource still exists."""
        resp = admin_client.post(
            "/api/v1/cdef_coverage/analyze",
            files=_files(("plan.json", _plan_bytes([("aws_ecs_service", ["delete", "create"])]))),
        )
        assert resp.status_code == 200
        assert {f["service"] for f in resp.json()["data"]["findings"]} == {"ecs"}

    def test_unrecognised_resource_is_a_gap_not_a_silence(self, admin_client):
        resp = admin_client.post(
            "/api/v1/cdef_coverage/analyze",
            files=_files(("azure.tfstate", _state_bytes(["azurerm_storage_account"]))),
        )
        assert resp.status_code == 200
        data = resp.json()["data"]

        finding = next(f for f in data["findings"] if f["service"] == "azurerm:storage")
        assert finding["verdict"] == "needs_custom"
        assert finding["inferred"] is True
        assert data["unmapped_resource_types"][0]["resource_type"] == "azurerm_storage_account"

    def test_rejects_a_non_terraform_file_by_name(self, admin_client):
        resp = admin_client.post(
            "/api/v1/cdef_coverage/analyze",
            files=_files(("notes.json", json.dumps({"hello": "world"}).encode())),
        )
        assert resp.status_code == 422
        assert "notes.json" in resp.json()["error"]

    def test_rejects_invalid_json_without_echoing_content(self, admin_client):
        resp = admin_client.post(
            "/api/v1/cdef_coverage/analyze",
            files=_files(("broken.tfstate", b'{"resources": ["' + FAKE_SECRET.encode() + b'"')),
        )
        assert resp.status_code == 422
        assert FAKE_SECRET not in resp.text


class TestSensitiveContent:
    """The property that makes accepting a state file acceptable at all."""

    def test_response_contains_no_attribute_values(self, admin_client):
        resp = admin_client.post(
            "/api/v1/cdef_coverage/analyze",
            files=_files(("rds.tfstate", _state_bytes(["aws_db_instance"]))),
        )
        assert resp.status_code == 200
        assert FAKE_SECRET not in resp.text
        assert FAKE_ACCOUNT not in resp.text
        # The TYPE name is kept — it identifies no account, region or secret.
        assert "aws_db_instance" in resp.text

    def test_saved_run_contains_no_attribute_values(self, admin_client):
        resp = admin_client.post(
            "/api/v1/cdef_coverage/runs",
            files=_files(("rds.tfstate", _state_bytes(["aws_db_instance"]))),
        )
        assert resp.status_code == 201, resp.text
        run_id = resp.json()["data"]["id"]

        fetched = admin_client.get(f"/api/v1/cdef_coverage/runs/{run_id}")
        assert fetched.status_code == 200
        assert FAKE_SECRET not in fetched.text
        assert FAKE_ACCOUNT not in fetched.text

        admin_client.delete(f"/api/v1/cdef_coverage/runs/{run_id}")

    def test_source_files_record_only_name_digest_and_counts(self, admin_client):
        resp = admin_client.post(
            "/api/v1/cdef_coverage/runs",
            files=_files(("prod.tfstate", _state_bytes(["aws_s3_bucket"]))),
        )
        assert resp.status_code == 201
        run = resp.json()["data"]

        source = run["source_files"][0]
        assert set(source) == {"filename", "digest", "format", "resource_count"}
        assert len(source["digest"]) == 64

        admin_client.delete(f"/api/v1/cdef_coverage/runs/{run['id']}")


class TestRuns:
    def test_save_analyze_then_list_and_delete(self, admin_client):
        created = admin_client.post(
            "/api/v1/cdef_coverage/runs",
            files=_files(("prod.tfstate", _state_bytes(["aws_guardduty_detector"]))),
        )
        assert created.status_code == 201
        run_id = created.json()["data"]["id"]

        listed = admin_client.get("/api/v1/cdef_coverage/runs")
        assert listed.status_code == 200
        assert any(r["id"] == run_id for r in listed.json()["data"])
        assert "meta" in listed.json()

        deleted = admin_client.delete(f"/api/v1/cdef_coverage/runs/{run_id}")
        assert deleted.status_code == 200

        gone = admin_client.get(f"/api/v1/cdef_coverage/runs/{run_id}")
        assert gone.status_code == 404

    def test_report_token_saves_without_reuploading(self, admin_client):
        analysed = admin_client.post(
            "/api/v1/cdef_coverage/analyze",
            files=_files(("prod.tfstate", _state_bytes(["aws_guardduty_detector"]))),
        )
        assert analysed.status_code == 200
        token = analysed.json()["data"]["report_token"]
        assert token
        analysed_counts = analysed.json()["data"]["counts"]

        saved = admin_client.post("/api/v1/cdef_coverage/runs", data={"report_token": token})
        assert saved.status_code == 201, saved.text
        saved_counts = saved.json()["data"]["counts"]

        # Assert the ROUND TRIP, not a particular verdict.
        #
        # This asserted `needs_custom >= 1`, which silently required GuardDuty to
        # have no Component Definition — true only while the AWS Labs corpus is
        # absent, which is the default (SPARC_AWS_LABS_CDEF_ENABLED=false) and so
        # held in CI. Enable the ingest and upstream's `guardduty` CDEF makes the
        # correct verdict `adopt`, not `needs_custom`, and the test failed for
        # reporting the right answer.
        #
        # What this test is actually for is that saving by report token yields
        # the same analysis as the upload did, without re-uploading. Comparing
        # the two count sets states that directly, is independent of which CDEFs
        # happen to be loaded, and is a stronger assertion than the original.
        assert saved_counts == analysed_counts, (
            "saving by report token must preserve the analysis verdicts: "
            f"analysed={analysed_counts} saved={saved_counts}"
        )
        # The state declares a service, so SOME verdict must have been recorded —
        # this keeps an empty report from satisfying the equality above.
        assert sum(saved_counts.values()) >= 1, f"no verdicts recorded: {saved_counts}"

        admin_client.delete(f"/api/v1/cdef_coverage/runs/{saved.json()['data']['id']}")

    def test_tampered_token_is_refused(self, admin_client):
        analysed = admin_client.post(
            "/api/v1/cdef_coverage/analyze",
            files=_files(("prod.tfstate", _state_bytes(["aws_s3_bucket"]))),
        )
        token = analysed.json()["data"]["report_token"]

        resp = admin_client.post("/api/v1/cdef_coverage/runs", data={"report_token": token + "x"})
        assert resp.status_code == 422


class TestAuthentication:
    def test_analyze_requires_a_token(self, anon_client):
        resp = anon_client.post(
            "/api/v1/cdef_coverage/analyze",
            files=_files(("prod.tfstate", _state_bytes(["aws_s3_bucket"]))),
        )
        assert resp.status_code == 401

    def test_runs_index_requires_a_token(self, anon_client):
        assert anon_client.get("/api/v1/cdef_coverage/runs").status_code == 401


class TestAuthorization:
    def test_non_admin_cannot_save_a_run(self, user_client):
        """SPARC_TEST_USER_TOKEN is a read-level account by contract (conftest).

        Asserted strictly rather than as ``in (403, 201)``: a test that accepts
        either answer proves nothing, and if this fails it means the token is
        over-privileged, which is worth failing over.
        """
        resp = user_client.post(
            "/api/v1/cdef_coverage/runs",
            files=_files(("prod.tfstate", _state_bytes(["aws_s3_bucket"]))),
        )
        assert resp.status_code == 403, (
            f"expected the read-level token to be denied cdef.write, got {resp.status_code}"
        )
