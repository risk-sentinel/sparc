# Boundary Onboarding Checklist

_The lifecycle a boundary moves through, from intake to steady state. For
connecting a team and a pipeline to SPARC see
[Onboarding a Team and a Pipeline](Onboarding-a-Team-and-a-Pipeline); this page
is about getting one **authorization boundary** to a state you can defend._

Each item names **what SPARC can see**, because the point of this list is that it
should eventually be derived rather than hand-ticked (#940). An item SPARC cannot
observe is marked as such, and that is a gap in SPARC, not in your process.

**Phases are ordered but not strictly gated** — Phase A work commonly starts
before Phase 0 is fully signed off. What matters is that you do not promote to
Delivery on an unresolved Authoritative layer.

---

## Phase 0 — Intake

| # | Item | Where SPARC holds it |
|---|------|----------------------|
| 0.1 | **System Owner, ISSO and a DevSecOps contact named** | Boundary personnel roster (`authorization_boundary_memberships`) |
| 0.2 | All other responsible parties named | Same roster — partial is normal early |
| 0.3 | **FIPS-199 categorization set**, with SP 800-60 information types | `SspDocument#security_sensitivity_level` |
| 0.4 | **Boundary definition and scope registered** | `AuthorizationBoundary#authorization_boundary_description` |

> **Known wrinkle.** Categorization lives on the **SSP**, not on the boundary, so
> 0.3 cannot be satisfied until an SSP exists — which is Phase A work. Either
> accept the ordering (record the categorization when the SSP is created) or
> treat 0.3 as a Phase A item. There is also **no dedicated SP 800-60
> information-types field**; if you need it recorded structurally today, use
> `boundary_metadata`. Worth resolving before this list is automated.

---

## Phase A — Authoritative

The layer everything else rests on. Do not skip ahead.

| # | Item | Where SPARC holds it |
|---|------|----------------------|
| A.1 | **Catalog and baseline bound** to the boundary | `AuthorizationBoundary#profile_document` |
| A.2 | Policy sources registered — NIST **and** your organization's | Authoritative sources |
| A.3 | **Core boundary documents ingested** — boundary definition, network diagram, dataflow diagram, inventory, PPSM, CRM | Back-matter resources |
| A.4 | **Back-matter registered *before* profile resolution**, with no dangling references | Back-matter resources + profile resolution |
| A.5 | **Profile resolves cleanly** — no unresolved imports | Profile document |
| A.6 | CDEFs bound, with control mappings | `AuthorizationBoundary#cdef_documents` |

> **A.4 fails closed for a reason.** A profile that resolves while carrying
> dangling back-matter references produces an export that looks complete and
> cites documents nobody registered. Register first, resolve second.

---

## Phase B — Validation

| # | Item | Where SPARC holds it |
|---|------|----------------------|
| B.1 | **Scanner wired; HDF artifacts arriving** | `AuthorizationBoundary#scan_runs` |
| B.2 | HDF is **fresh** — a recent run, not last quarter's | `ScanRun#ingested_at` |
| B.3 | Validation checks bound to the capabilities they evidence | Scan runs ↔ CDEF binding |
| B.4 | **Latest threshold run passes** | Scan run results |

Content that is not natively HDF is converted **upstream** — `saf convert
xccdf_results2hdf` for SCAP, `cis-bench` for CIS Benchmarks. Those tools resolve
NIST controls themselves and SPARC reads the result (#1033); you do not need to
map them inside SPARC.

Push scan results to:

```
POST /api/v1/authorization_boundaries/:authorization_boundary_id/scan_runs
```

---

## Phase C — Delivery

| # | Item | Where SPARC holds it |
|---|------|----------------------|
| C.1 | Boundary documents generated as build outputs, not hand-maintained | Document generation |
| C.2 | **OSCAL package exports and validates** — SSP, CDEFs, assessment results, POA&M | `ssp_document`, `cdef_documents`, `sar_document`, `poam_documents` |
| C.3 | Downstream target configured (eMASS, Xacta, VDR, or your equivalent) | **Not modelled in SPARC today** — record it in your pipeline |

---

## Phase D — Federation

_Only if you are leveraging, or being leveraged by, another boundary._

| # | Item | Where SPARC holds it |
|---|------|----------------------|
| D.1 | **PKI trust established in both directions** | Federation peers |
| D.2 | Validated OSCAL and inheritance shared | `leveraged_relationships` / `leveraging_relationships` |
| D.3 | The degraded path — operating **without** federated trust — has been exercised | Not observable; exercise it deliberately |

> D.3 is the one people skip. A federation that has never been tested without
> its trust path will discover that path's importance at the worst moment.

---

## Phase E — Steady state

| # | Item | Where SPARC holds it |
|---|------|----------------------|
| E.1 | Scan + convert + validate run on a **cadence in CI**, not by hand | Your pipeline |
| E.2 | Document regeneration wired, with a stale-artifact gate | Your pipeline |
| E.3 | A new capability requires **CDEF + check + HDF** together, as one unit | Policy, enforced in review |

> E.3 is what stops drift. A capability that ships with a CDEF but no check has
> a claim nobody evidences; one with a check but no CDEF produces findings that
> map to nothing.

---

## Why this list exists in this shape

Every item names where SPARC holds the answer, because a checklist a person
ticks is unverifiable and drifts the moment the boundary changes. **#940** turns
this into a derived report — `readiness` — that reads the registered state and
reports green/amber/red per item, with the evidence it computed from.

Two items above are honestly **not observable** today (C.3 downstream target,
D.3 degraded-mode exercise) and one is observable only indirectly (0.3
categorization, which lives on the SSP). Those are named rather than quietly
dropped, because a readiness report that silently omits what it cannot see is
worse than one that says "I cannot check this."

## Related

- [Onboarding a Team and a Pipeline](Onboarding-a-Team-and-a-Pipeline) — people and pipelines
- [OSCAL End-to-End](OSCAL-End-to-End) — what the artifacts become
- [Authorization Boundaries](User-Guide-Authorization-Boundaries) — the screens
