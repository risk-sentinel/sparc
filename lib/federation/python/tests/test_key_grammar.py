"""The Python port asserted against the shared vectors (#1161).

Every vector, assertion, join-case and rejection in ``key-grammar.v1.json`` is
exercised here. The file is the contract between three runtimes, so a test that
restated its expectations instead of reading them would prove nothing about
agreement — which is the only property this port exists to have.
"""

from __future__ import annotations

import json
import uuid as _uuid

import pytest

from sparc_federation import key as K


@pytest.fixture(scope="module")
def spec() -> dict:
    return json.loads(K.GRAMMAR_PATH.read_text())


def test_namespace_is_registered_not_provisional(spec: dict) -> None:
    """The provisional namespace was superseded when sparc#1155 landed."""
    assert spec["namespace"]["provisional"] is False
    assert spec["namespace"]["uuid"] == "9f434272-f796-589b-b972-954790395630"


def test_namespace_is_the_uuid5_of_the_registered_uri(spec: dict) -> None:
    """Recomputed, not repeated — the whole point of deriving it."""
    recomputed = _uuid.uuid5(_uuid.NAMESPACE_URL, "https://sparc.risk-sentinel.org/ns")
    assert str(recomputed) == spec["namespace"]["uuid"]


def test_separator_is_the_unit_separator(spec: dict) -> None:
    assert spec["separator"] == "\x1f"


class TestVectors:
    def test_every_vector_derives_its_uuid(self, spec: dict) -> None:
        failures = []
        for v in spec["vectors"]:
            got = K.derive(v["kind"], v["args"])
            if got != v["uuid"]:
                failures.append(f"{v['name']}: expected {v['uuid']} got {got}")
        assert not failures, "\n".join(failures)

    def test_every_vector_reproduces_its_canonical_fields(self, spec: dict) -> None:
        """The field lists must GENERATE the published fields, not merely agree
        with a UUID that happens to match."""
        failures = []
        for v in spec["vectors"]:
            got = K.canonical_fields(v["kind"], v["args"])
            if got != v["canonical-fields"]:
                failures.append(f"{v['name']}:\n  expected {v['canonical-fields']}\n  got      {got}")
        assert not failures, "\n".join(failures)

    def test_all_nine_kinds_are_covered(self, spec: dict) -> None:
        assert set(spec["field-lists"]) == {v["kind"] for v in spec["vectors"]}


class TestAssertions:
    """The relations the vectors exist to demonstrate, read from the file."""

    def test_declared_relations_hold(self, spec: dict) -> None:
        by_name = {v["name"]: v for v in spec["vectors"]}
        failures = []
        for a in spec["assertions"]:
            uuids = [K.derive(by_name[n]["kind"], by_name[n]["args"]) for n in a["vectors"]]
            if a["relation"] == "distinct":
                if len(set(uuids)) != len(uuids):
                    failures.append(f"{a['name']}: expected all distinct, got {uuids}")
            elif a["relation"] == "same":
                if len(set(uuids)) != 1:
                    failures.append(f"{a['name']}: expected all equal, got {uuids}")
            else:
                failures.append(f"{a['name']}: unknown relation {a['relation']!r}")
        assert not failures, "\n".join(failures)

    def test_there_are_assertions_to_check(self, spec: dict) -> None:
        """A relation set that silently emptied would make the test above vacuous."""
        assert len(spec["assertions"]) >= 10


class TestJoinAmbiguity:
    def test_a_printable_delimiter_would_collide_but_this_one_does_not(self, spec: dict) -> None:
        """('a|b','c') and ('a','b|c') must derive DIFFERENT uuids."""
        cases = spec["join-cases"]
        derived = []
        for case in cases:
            joined = spec["grammar"] + spec["separator"] + spec["separator"].join(case["fields"])
            got = str(_uuid.uuid5(_uuid.UUID(spec["namespace"]["uuid"]), joined))
            assert got == case["uuid"], f"{case['name']}: expected {case['uuid']} got {got}"
            derived.append(got)
        assert len(set(derived)) == len(derived), "the join cases collided"


class TestRejections:
    def test_every_declared_rejection_is_refused(self, spec: dict) -> None:
        failures = []
        for r in spec["rejections"]:
            try:
                K.derive(r["kind"], r["args"])
            except (K.MissingField, K.InvalidField, K.SeparatorInField):
                continue
            except Exception as exc:  # noqa: BLE001 - a wrong error is still a failure
                failures.append(f"{r['name']}: wrong exception {type(exc).__name__}: {exc}")
            else:
                failures.append(f"{r['name']}: was NOT rejected — {r['why']}")
        assert not failures, "\n".join(failures)

    def test_a_field_carrying_the_separator_is_rejected_not_escaped(self) -> None:
        with pytest.raises((K.SeparatorInField, K.InvalidField)):
            K.derive(
                "observation",
                {
                    "parent-ssp-uuid": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
                    "source-uuid": "b7e21d90-4c1a-4f55-9e33-0a6d2c118f44",
                    "vocabulary": "opaque",
                    "control-id": "ACM\x1f1",
                    "component-uuid": "9f1c0f4e-2b7a-4d61-8f52-1c9a3b7d4e60",
                    "period": "2026-Q3",
                },
            )


class TestVocabularyGovernsNormalisation:
    """23 of 26 vectors carry a `vocabulary` that is never hashed.

    A port that hashed every argument, or that canonicalised unconditionally,
    would derive different UUIDs for every Security Hub object — and nothing
    would surface it.
    """

    BASE = {
        "parent-ssp-uuid": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
        "source-uuid": "b7e21d90-4c1a-4f55-9e33-0a6d2c118f44",
        "component-uuid": "9f1c0f4e-2b7a-4d61-8f52-1c9a3b7d4e60",
        "period": "2026-Q3",
    }

    def test_vocabulary_is_not_hashed(self, spec: dict) -> None:
        assert spec["context-args"] == ["vocabulary"]
        fields = K.canonical_fields("observation", {**self.BASE, "vocabulary": "nist-sp800-53", "control-id": "cp-4"})
        assert "nist-sp800-53" not in fields

    def test_nist_spellings_converge(self) -> None:
        a = K.derive("observation", {**self.BASE, "vocabulary": "nist-sp800-53", "control-id": "AC-2 (1)"})
        b = K.derive("observation", {**self.BASE, "vocabulary": "nist-sp800-53", "control-id": "ac-2.1"})
        assert a == b

    def test_opaque_identifiers_keep_their_case_and_stay_distinct(self) -> None:
        """`ACM.1` and `acm.1` are two Security Hub controls, not two spellings."""
        upper = K.derive("observation", {**self.BASE, "vocabulary": "opaque", "control-id": "ACM.1"})
        lower = K.derive("observation", {**self.BASE, "vocabulary": "opaque", "control-id": "acm.1"})
        assert upper != lower

    def test_vocabulary_is_required_rather_than_defaulted(self) -> None:
        with pytest.raises(K.MissingField):
            K.derive("observation", {**self.BASE, "control-id": "cp-4"})


class TestUnicode:
    def test_fields_are_nfc_normalised(self) -> None:
        """Composed and decomposed forms of one string are one object."""
        base = {
            "parent-ssp-uuid": "3fa85f64-5717-4562-b3fc-2c963f66afa6",
            "source-uuid": "b7e21d90-4c1a-4f55-9e33-0a6d2c118f44",
            "component-uuid": "9f1c0f4e-2b7a-4d61-8f52-1c9a3b7d4e60",
            "period": "2026-Q3",
            "vocabulary": "opaque",
        }
        composed = K.derive("observation", {**base, "control-id": "étape"})
        decomposed = K.derive("observation", {**base, "control-id": "étape"})
        assert composed == decomposed


class TestDedupScoping:
    """#1159 — dedup scopes on (object UUID, originating party).

    Only sound now that the runtimes provably agree on the UUID, which is why
    #1161 ships before it.
    """

    def test_every_declared_case_holds(self, spec: dict) -> None:
        failures = []
        for case in spec["dedup"]["cases"]:
            if case["expect"].get("reject"):
                try:
                    K.dedup(case["claims"])
                except K.MissingField:
                    continue
                failures.append(f"{case['name']}: was NOT rejected — {case['why']}")
                continue

            objects, conflicts = K.dedup(case["claims"])
            if len(objects) != case["expect"]["objects"] or len(conflicts) != case["expect"]["conflicts"]:
                failures.append(
                    f"{case['name']}: expected {case['expect']}, "
                    f"got objects={len(objects)} conflicts={len(conflicts)}"
                )
        assert not failures, "\n".join(failures)

    def test_there_are_cases_to_check(self, spec: dict) -> None:
        assert len(spec["dedup"]["cases"]) >= 5

    def test_the_key_is_the_pair_never_the_uuid_alone(self, spec: dict) -> None:
        assert spec["dedup"]["key"] == ["object-uuid", "originating-party"]

    def test_two_parties_on_one_uuid_keeps_both_and_surfaces_it(self) -> None:
        """The attack the rule exists for.

        A peer precomputes another boundary's identifier and claims it. Keeping
        one silently is the failure mode, whichever one it keeps.
        """
        uuid_value = "73b4b970-e2ba-5e5e-884a-7c7de1600e95"
        objects, conflicts = K.dedup(
            [
                {"object-uuid": uuid_value, "originating-party": "party-a"},
                {"object-uuid": uuid_value, "originating-party": "party-b"},
            ]
        )
        assert len(objects) == 2
        assert len(conflicts) == 1
        assert conflicts[0]["parties"] == ["party-a", "party-b"]

    def test_one_conflict_per_contested_uuid_not_per_excess_claim(self) -> None:
        uuid_value = "73b4b970-e2ba-5e5e-884a-7c7de1600e95"
        claims = [{"object-uuid": uuid_value, "originating-party": p} for p in "abcd"]

        _objects, conflicts = K.dedup(claims)

        assert len(conflicts) == 1

    def test_a_claim_with_no_party_is_refused(self) -> None:
        with pytest.raises(K.MissingField):
            K.dedup([{"object-uuid": "73b4b970-e2ba-5e5e-884a-7c7de1600e95", "originating-party": ""}])
