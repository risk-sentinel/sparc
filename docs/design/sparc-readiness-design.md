# `sparc readiness` — Design Spec

**Status:** Draft · **Owner:** SPARC core · **Target repo:** `risk-sentinel/sparc`
**Related:** `ONBOARDING.md` (boundary onboarding checklist), `sparc-validate`

---

## 1. Summary

`sparc readiness` turns the boundary onboarding checklist from a hand-ticked
document into a **build output**. Instead of asking a human "did you register the
boundary documents / bind the CDEFs / land a passing validation?", the command
introspects the boundary's actual registered state across SPARC's three layers
(Authoritative → Validation → Delivery) and emits a per-item **green / amber / red**
verdict, plus a gate result suitable for failing a pipeline.

The guiding principle: **the report reflects what SPARC can actually see, not what
someone claims.** A person can tick "inventory registered" and be wrong; a derived
check reads the registration directly and cannot.

---

## 2. Goals / non-goals

**Goals**
- One command that scores a boundary against a declarative catalog of readiness checks.
- Deterministic, machine-readable output (JSON) plus human table and Markdown.
- A CI gate: `--gate C` exits non-zero unless the boundary is green through phase C.
- Checks defined declaratively (YAML) so they are portable and reviewable, not buried in code.
- Optionally emit the readiness result as an OSCAL artifact (SPARC dogfooding itself).

**Non-goals**
- It does not *perform* control assessment — that is `saf validate` / the Validation Layer. Readiness reads the *result* of validation, it does not replace it.
- It does not mutate boundary state. Read-only by contract.
- It does not replace the human sign-off (AO/ISSO); it informs it.

---

## 3. Command surface

```
sparc readiness <boundary-id> [flags]

Flags:
  --format table|json|markdown|junit     Output format (default: table)
  --phase <0|A|B|C|D|E>                  Evaluate/print only one phase
  --gate  <0|A|B|C|D|E>                  Gate mode: exit non-zero unless green through <phase>
  --fail-on red|amber                    Severity that fails the gate (default: red)
  --out <path>                           Write report to file instead of stdout
  --checks <dir>                         Override check-catalog directory
  --emit-oscal <path>                    Additionally write an OSCAL assessment-results file
  --no-color                             Plain output for logs
```

Examples:

```bash
# Human review during onboarding
sparc readiness acme-prod

# CI gate: block promotion to Delivery until green through phase C
sparc readiness acme-prod --gate C --format junit --out readiness.xml

# Machine consumption / dashboards
sparc readiness acme-prod --format json --out readiness.json
```

---

## 4. Status model

Every check resolves to exactly one status:

| Status | Meaning | Typical cause |
|--------|---------|---------------|
| 🟢 `green` | Satisfied | Probe fully met |
| 🟡 `amber` | Partial | Present but incomplete (e.g. some CDEFs unbound, some parties unnamed) |
| 🔴 `red` | Missing / failing | Not registered, or fails closed (e.g. profile has dangling refs) |
| ⚪ `na` | Not applicable | Conditional check whose precondition is false (e.g. federation when not federating) |

**Blocking vs. advisory.** Each check declares `blocking: true|false`. A blocking
`red` fails its phase gate; a non-blocking `amber`/`red` is reported but does not
fail the default gate (it fails only under `--fail-on amber`).

**Phase rollup.** A phase is:
- `green` if every applicable check is `green`,
- `amber` if no blocking `red` but at least one `amber`,
- `red` if any blocking check is `red`.

**Gate verdict.** `--gate X` passes iff phase `X` **and every earlier phase** roll
up to `green` (or `amber` when `--fail-on` allows it). Phases are ordered
`0 < A < B < C < D < E`; `D` (Federation) is skipped when all its checks are `na`.

**Exit codes** (for CI):
| Code | Meaning |
|------|---------|
| `0` | Gate satisfied |
| `1` | One or more blocking `red` within gate scope |
| `2` | `amber` within gate scope and `--fail-on amber` set |
| `3` | Introspection/config error (boundary not found, bad catalog) |

---

## 5. Check definition format

Checks are declarative YAML under `readiness/checks/*.yaml`. This keeps the catalog
portable and reviewable, and lets a boundary add org-specific checks without
touching SPARC code.

```yaml
- id: AUTH-BACKMATTER
  phase: A                       # 0|A|B|C|D|E
  layer: authoritative           # authoritative|validation|delivery
  title: Boundary documents ingested and back-matter registered
  blocking: true
  applies_when: always           # always | federating | has-leveraged | expr(...)
  probe:
    kind: backmatter-coverage    # named probe implemented by the introspector
    required:
      - boundary-definition
      - network-diagram
      - dataflow-diagram
      - inventory
      - ppsm
      - crm
  status:                        # first matching rule wins
    green: "coverage == 1.0 && dangling_refs == 0"
    amber: "coverage > 0"
    red:   "coverage == 0 || dangling_refs > 0"
  remediation: >
    Ingest and register the missing resources in the Authoritative Layer before
    profile resolution. See ONBOARDING §2. Dangling references fail closed.
  doc_ref: "ONBOARDING.md#2-boundary--and-organization-specific-documents"
```

**Probe kinds** (the introspector implements each against SPARC's state store):

| `probe.kind` | Reads | Returns |
|--------------|-------|---------|
| `responsible-parties` | `metadata/responsible-party` | set of named roles |
| `field-present` | any Authoritative field (e.g. FIPS-199) | bool |
| `resource-coverage` | registered documents / back-matter | ratio + missing list |
| `backmatter-coverage` | back-matter + profile resolution graph | coverage + dangling-ref count |
| `cdef-binding` | bound component-definitions | covered/partial/missing counts |
| `hdf-presence` | Validation Layer HDF artifacts | latest timestamp, count |
| `threshold-result` | last `saf validate` result | pass/fail + margins |
| `export-manifest` | Delivery Layer export record | present + freshness + OSCAL-valid |
| `ci-policy` | pipeline config introspection | rule present (cadence, doc-regen gate) |
| `federation-trust` | PKI trust store | trust established / degraded-ok |

---

## 6. Check catalog (v1)

Mapped 1:1 to the onboarding checklist. IDs are stable; add, never renumber.

### Phase 0 — Intake
| ID | Check | Blocking | Green when |
|----|-------|----------|-----------|
| `INTAKE-PERS-MIN` | System Owner + ISSO + DevSecOps named | ✅ | all three present |
| `INTAKE-PERS-FULL` | All responsible parties named | — | full §1 set present (amber if partial) |
| `INTAKE-CATEGORIZATION` | FIPS-199 + SP 800-60 set | ✅ | both present |
| `INTAKE-SCOPE` | Boundary definition/scope registered | ✅ | present |

### Phase A — Authoritative
| ID | Check | Blocking | Green when |
|----|-------|----------|-----------|
| `AUTH-CATALOG` | Catalog(s) + baseline loaded | ✅ | ≥1 baseline bound |
| `AUTH-POLICY` | Policy sources registered (NIST **and** org) | — | both source classes present |
| `AUTH-DOCS-CORE` | Core boundary docs ingested (§2 core) | ✅ | coverage == 1.0 |
| `AUTH-BACKMATTER` | Back-matter registered before resolution | ✅ | coverage == 1.0 && no dangling refs |
| `AUTH-PROFILE-RESOLVE` | Profile resolves cleanly | ✅ | resolution success, 0 unresolved imports |
| `AUTH-CDEF-BIND` | CDEFs bound with control mappings | — | covered ratio == 1.0 (amber if partial) |

### Phase B — Validation
| ID | Check | Blocking | Green when |
|----|-------|----------|-----------|
| `VAL-SAF-WIRED` | SAF CLI wired; HDF artifacts observed | ✅ | ≥1 HDF artifact seen |
| `VAL-HDF-FRESH` | HDF within freshness window | — | latest HDF ≤ `freshness_days` (default 7) |
| `VAL-CHECKS-BOUND` | Validation checks bound to capabilities | — | coverage ratio ≥ threshold (amber below) |
| `VAL-THRESHOLD` | Latest `saf validate` threshold passes | ✅ | last run pass |

### Phase C — Delivery
| ID | Check | Blocking | Green when |
|----|-------|----------|-----------|
| `DEL-DOCS-GEN` | Boundary docs generated as build outputs | — | regeneration manifest present + current |
| `DEL-OSCAL-EXPORT` | OSCAL package exports & validates (v1.2.2) | ✅ | SSP + CDEFs + assessment + POA&M valid |
| `DEL-TARGET` | Downstream target configured | — | Xacta/eMASS/VDR target set |

### Phase D — Federation (`applies_when: federating`)
| ID | Check | Blocking | Green when |
|----|-------|----------|-----------|
| `FED-PKI-TRUST` | PKI trust established (leveraged ↔ leveraging) | ✅ | trust verified both directions |
| `FED-INHERIT-SHARE` | Validated OSCAL / inheritance shared | — | shared artifacts present |
| `FED-DEGRADED-MODE` | Operates without federated PKI trust | — | degraded path exercised |

### Phase E — Steady state
| ID | Check | Blocking | Green when |
|----|-------|----------|-----------|
| `SS-CADENCE` | Scan + `convert`/`validate` cadence in CI | — | schedule/gate present |
| `SS-DOC-REGEN` | Doc regeneration wired (stale-diagram gate) | — | CI rule present |
| `SS-CDEF-CURATION` | New capability requires CDEF + check + HDF triple | — | policy gate present |

---

## 7. Output contract (JSON)

```json
{
  "schema": "sparc.readiness/v1",
  "boundary": "acme-prod",
  "generated": "<ISO-8601>",
  "oscal_version": "1.2.2",
  "gate": { "requested": "C", "verdict": "red", "fail_on": "red" },
  "summary": { "green": 12, "amber": 3, "red": 2, "na": 3, "total": 20 },
  "phases": [
    {
      "phase": "A",
      "title": "Authoritative",
      "rollup": "amber",
      "checks": [
        {
          "id": "AUTH-BACKMATTER",
          "title": "Boundary documents ingested and back-matter registered",
          "status": "green",
          "blocking": true,
          "evidence": { "coverage": 1.0, "dangling_refs": 0, "missing": [] },
          "remediation": null,
          "doc_ref": "ONBOARDING.md#2-..."
        },
        {
          "id": "AUTH-CDEF-BIND",
          "title": "CDEFs bound with control mappings",
          "status": "amber",
          "blocking": false,
          "evidence": { "covered": 9, "partial": 2, "missing": 1, "ratio": 0.75 },
          "remediation": "Author/bind CDEFs for: <component>. See ONBOARDING §4.",
          "doc_ref": "ONBOARDING.md#4-..."
        }
      ]
    }
  ]
}
```

Key properties:
- `evidence` carries the *raw numbers the verdict was computed from* — so the report is auditable, not just a color.
- `remediation` is populated only for non-green checks and points back to the onboarding doc.
- The shape is stable under `schema` versioning; new fields are additive.

`--format junit` maps each check to a `<testcase>` (fail = blocking red) so any CI
can render it natively. `--format markdown` renders §6-style tables for a PR comment.

---

## 8. OSCAL emission (`--emit-oscal`)

Because readiness *is* an assessment of the boundary's compliance posture, it can be
expressed as OSCAL `assessment-results` — making SPARC dogfood its own model:
- each readiness check → an `observation` (with `evidence` as `relevant-evidence`),
- each blocking `red` → a `finding` linked to the affected component/control,
- the phase gate → a top-level `result` summary.

This lets the readiness report itself flow through the same Delivery Layer and VDR
handoff as every other OSCAL artifact.

---

## 9. CI integration (GitLab)

```yaml
readiness:
  stage: compliance
  script:
    - sparc readiness "$BOUNDARY_ID" --gate C --fail-on red --format junit --out readiness.xml
    - sparc readiness "$BOUNDARY_ID" --format markdown --out readiness.md
  artifacts:
    when: always
    reports:
      junit: readiness.xml
    paths: [readiness.md, readiness.json]
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
```

The gate runs on every pipeline; promotion to the next phase is blocked until the
boundary is green through the required phase. The Markdown artifact can be posted as
an MR comment; the JSON feeds the SPARC UI readiness card.

---

## 10. UI surface

A **Readiness** card/screen per boundary (consistent with SPARC's card/list toggle
direction): phase rollup chips (🟢🟡🔴), expandable per-check rows showing `evidence`
and `remediation`, and a one-click "export readiness" (JSON / Markdown / OSCAL).
Search/filter by phase, layer, and status like every other SPARC screen.

---

## 11. Open questions

- Freshness windows (`VAL-HDF-FRESH`) — global default vs. per-boundary override in Authoritative metadata?
- Should `AUTH-CDEF-BIND` treat `partial` CDEFs as amber or configurable-blocking per boundary risk tier?
- `--gate` semantics for `na` phases: skip (current design) vs. require explicit `--allow-skip D`.
- Where the check catalog lives: vendored in `sparc` vs. a shareable `risk-sentinel/sparc-readiness-checks` repo for cross-org reuse.
