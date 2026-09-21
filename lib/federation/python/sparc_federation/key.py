"""Reference implementation of the UUIDv5 object-key grammar (#1161).

The grammar is specified normatively in sparc-horizon ``docs/03-data-model.md``,
section *Deterministic UUIDs*. Identifiers derived under it are exchanged between
instances, so **a disagreement between two implementations is a silent
data-integrity fault, not a bug someone notices**: the same logical object arrives
under a second identity and nothing reconciles it.

::

    namespace  = 9f434272-f796-589b-b972-954790395630   (registered, sparc#1155)
    grammar    = "v1"
    uuid(obj)  = uuidv5(namespace, grammar + "\\x1f" + join(fields(obj), "\\x1f"))

Why this reads a data file instead of declaring the fields here
---------------------------------------------------------------
The field lists live in ``key-grammar.v1.json`` and are read at import time, so
Ruby, Python and Go build keys from ONE declaration rather than three
transcriptions. Every ``canonical-fields`` in that file is regenerated from the
same field lists, so the vectors and the rule they encode cannot drift apart.

What this does NOT do (#1161 scope)
-----------------------------------
Nothing derives object UUIDs through this yet. It is a reference implementation
and its vectors; wiring it into real objects is separate work.
"""

from __future__ import annotations

import json
import re
import unicodedata
import uuid as _uuid
from pathlib import Path
from typing import Any

GRAMMAR_PATH = Path(__file__).resolve().parents[2] / "key-grammar.v1.json"


class SeparatorInField(ValueError):
    """Rejected rather than escaped.

    A printable delimiter would make ``("a|b","c")`` and ``("a","b|c")`` hash
    identically — a collision by accident, harder to notice than one by attack.
    ``\\x1f`` cannot appear in any defined field, so a field carrying it is a
    caller error, not something to repair.
    """


class MissingField(ValueError):
    """A key missing a field is a DIFFERENT key, not a key with an empty field."""


class InvalidField(ValueError):
    """A field whose value cannot be what it claims to be.

    ``2026-1`` is not a spelling of ``2026-01``, and a component named
    ``web-01`` does not federate.
    """


class UnknownKind(ValueError):
    """No field list is declared for this object kind."""


def spec() -> dict[str, Any]:
    """The grammar declaration, read once."""
    global _SPEC
    if _SPEC is None:
        _SPEC = json.loads(GRAMMAR_PATH.read_text())
    return _SPEC


_SPEC: dict[str, Any] | None = None

# Under NIST the canonicalised value must name a control or an enhancement. This
# rejects a statement fragment (`ac-2_smt.a`, which names part of a control, so
# keying on it counts one object twice) and a foreign-vocabulary identifier
# declared as NIST (`ACM.1` canonicalises to `acm.1`, which validates against
# nothing). Under an opaque vocabulary any non-empty value passes unchanged.
NIST_CONTROL_FORM = re.compile(r"\A[a-z]{2,3}-\d+(\.\d+)*\Z")

_UUID = re.compile(r"\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\Z")
_PERIOD = re.compile(r"\A\d{4}-(Q[1-4]|0[1-9]|1[0-2])\Z")
_DATE = re.compile(r"\A\d{4}-\d{2}-\d{2}\Z")
_SHA256 = re.compile(r"\A[0-9a-f]{64}\Z")
_FAMILY = re.compile(r"\A[a-z]{2,3}\Z")

TYPE_RULES = {
    "uuid": lambda v: bool(_UUID.match(v)),
    "family-id": lambda v: bool(_FAMILY.match(v)),
    "period": lambda v: bool(_PERIOD.match(v)),
    "decision-date": lambda v: bool(_DATE.match(v)),
    "sha256": lambda v: bool(_SHA256.match(v)),
    "half": lambda v: v in ("provider", "consumer"),
    "horizon-bucket": lambda v: v in ("today", "+7", "+14", "+30") or bool(_DATE.match(v)),
}

_MAX_PADDED_DIGITS = 3


def _strip_padding(value: str) -> str:
    def repl(m: re.Match[str]) -> str:
        lead, zeros, digits = m.group(1), m.group(2), m.group(3)
        keep = digits if len(zeros) + len(digits) <= _MAX_PADDED_DIGITS else zeros + digits
        return f"{lead}{keep}"

    return re.sub(r"(\A|[-.])(0+)(\d+)", repl, value)


def canonical_control_id(raw: Any) -> str:
    """Port of SPARC's ``ControlId.canonical``.

    Differential-tested against the Ruby across the spelling vectors and a wider
    input set; the two must not diverge, because the grammar normalises control
    identifiers *before* derivation and a disagreement here produces two UUIDs
    for one object.
    """
    if raw is None or str(raw).strip() == "":
        return "unknown"
    s = str(raw).strip().lower()
    s = re.sub(r"\s+", "-", s)
    s = s.replace("(", ".").replace(")", "")
    s = re.sub(r"\.{2,}", ".", s)
    # A literal two-character replacement, so str.replace rather than re.sub —
    # identical semantics (non-overlapping, left to right) to Ruby's
    # `gsub(/-\./, ".")`, without compiling a pattern for a fixed string.
    s = s.replace("-.", ".")
    return _strip_padding(s)


NORMALISERS = {
    "control-id": canonical_control_id,
    "lowercase": lambda v: str(v).lower(),
    "none": lambda v: str(v),
    None: lambda v: str(v),
}


def _fetch(args: dict[str, Any], name: str) -> Any:
    return args.get(name)


def _present(args: dict[str, Any], name: str) -> bool:
    return str(_fetch(args, name) or "").strip() != ""


def _nfc(value: Any) -> str:
    return unicodedata.normalize("NFC", str(value))


def _vocabulary_rule(args: dict[str, Any]) -> str:
    """The vocabulary decides how a control identifier is normalised.

    NOT defaulted: without one there is no way to know whether the identifier may
    be canonicalised, and guessing NIST would canonicalise a foreign identifier
    into something that validates and names nothing.
    """
    vocabulary = str(_fetch(args, "vocabulary") or "").strip()
    if not vocabulary:
        raise MissingField("vocabulary is required for an object carrying a control identifier")
    rules = spec()["vocabulary-normalisers"]
    if vocabulary not in rules:
        raise InvalidField(f"unknown vocabulary {vocabulary!r} (known: {', '.join(rules)})")
    return rules[vocabulary]


def _normalise(rule: str | None, value: Any, args: dict[str, Any]) -> str:
    if rule == "by-vocabulary":
        rule = _vocabulary_rule(args)
    if rule not in NORMALISERS:
        raise ValueError(f"unknown normaliser {rule!r}")
    return NORMALISERS[rule](value)


def _validate(kind: str, name: str, type_: str | None, value: str, args: dict[str, Any]) -> None:
    """Validated AFTER normalisation, because that is the value the key is built from."""
    if type_ is None:
        return
    if type_ == "control-id":
        ok = bool(value) if _vocabulary_rule(args) == "none" else bool(NIST_CONTROL_FORM.match(value))
    else:
        ok = TYPE_RULES[type_](value)
    if not ok:
        raise InvalidField(
            f"{kind}: {name} {value!r} is not a valid {type_} ({spec()['types'][type_]})"
        )


def _resolve(kind: str, field_spec: dict[str, Any], args: dict[str, Any]) -> str:
    if "literal" in field_spec:
        return _nfc(field_spec["literal"])

    if "one-of" in field_spec:
        chosen = next((c for c in field_spec["one-of"] if _present(args, c)), None)
        if chosen is None:
            raise MissingField(f"{kind}: none of {' / '.join(field_spec['one-of'])} supplied")
        name = chosen
        rule = field_spec["normalise"][chosen]
        type_ = field_spec["type"][chosen]
    else:
        name = field_spec["arg"]
        rule = field_spec.get("normalise")
        type_ = field_spec.get("type")

    if not _present(args, name):
        raise MissingField(f"{kind}: {name} is required and was not supplied")

    value = _nfc(_normalise(rule, _fetch(args, name), args))
    _validate(kind, name, type_, value, args)
    return value


def canonical_fields(kind: str, args: dict[str, Any]) -> list[str]:
    """The grammar version followed by each normalised, NFC-folded field.

    Exposed because it is what a disagreement is diagnosed from — comparing two
    UUIDs tells you only that they differ.
    """
    lists = spec()["field-lists"]
    if kind not in lists:
        raise UnknownKind(f"unknown object kind {kind!r} (known: {', '.join(lists)})")

    separator = spec()["separator"]
    fields = [_resolve(kind, fs, args) for fs in lists[kind]]
    for value in fields:
        if separator in value:
            raise SeparatorInField(f"{kind}: a field contains the grammar separator")
    return [spec()["grammar"]] + fields


def derive(kind: str, args: dict[str, Any]) -> str:
    """The object's UUID under the registered federation namespace."""
    separator = spec()["separator"]
    namespace = _uuid.UUID(spec()["namespace"]["uuid"])
    return str(_uuid.uuid5(namespace, separator.join(canonical_fields(kind, args))))


def dedup(claims: list[dict[str, Any]]) -> tuple[list[dict[str, str]], list[dict[str, Any]]]:
    """Deduplicate a set of claims (#1159).

    **An object UUID identifies a thing, not an assertion about a thing.** The
    asserting party is never folded into the key — deliberately, because that is
    what lets two peers recognise the same object without coordinating. The cost
    is that the grammar is public and the namespace shared, so ANY peer can
    compute ANY boundary's identifiers. Determinism is being used as an
    addressing scheme, and addressing needs an owner.

    So dedup scopes on the PAIR. Keying on the UUID alone would let a hostile
    peer precompute another boundary's attestation identifier and submit a
    document claiming it; the receiver would then treat two parties' assertions
    about different things as one object, and which survives would be a property
    of ingestion order rather than authority.

    Two parties on one UUID is a CONFLICT TO SURFACE, never a duplicate to
    collapse. Both are kept: silently keeping one is the failure mode, whichever
    one it keeps.

    Returns ``(objects, conflicts)``. ``objects`` is one entry per distinct pair;
    ``conflicts`` is one entry per CONTESTED UUID, not per excess claim, so the
    count does not grow with how many peers pile on.
    """
    scoped: list[dict[str, str]] = []
    for claim in claims:
        uuid_value = str(claim.get("object-uuid") or claim.get("object_uuid") or "")
        party = str(claim.get("originating-party") or claim.get("originating_party") or "")
        if not party.strip():
            raise MissingField(
                "a claim carries no originating party — it cannot be scoped, and defaulting "
                "it would recreate dedup-by-uuid for exactly the claims that skipped verification"
            )
        if not uuid_value.strip():
            raise MissingField("a claim carries no object uuid")
        scoped.append({"object-uuid": uuid_value, "originating-party": party})

    objects: list[dict[str, str]] = []
    for entry in scoped:
        if entry not in objects:
            objects.append(entry)

    by_uuid: dict[str, list[str]] = {}
    for entry in objects:
        by_uuid.setdefault(entry["object-uuid"], []).append(entry["originating-party"])

    conflicts = [
        {"object-uuid": uuid_value, "parties": sorted(parties)}
        for uuid_value, parties in by_uuid.items()
        if len(parties) > 1
    ]
    return objects, conflicts
