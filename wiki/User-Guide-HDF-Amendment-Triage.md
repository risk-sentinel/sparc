# User Guide: HDF Amendment Triage

Turn raw scanner output into auditable disposition decisions. Upload your
scanners' findings (in HDF — the Heimdall Data Format the SAF CLI produces),
triage each failed control through a guided UI, and export an **HDF Amendments**
document your CI applies with `hdf amend apply` before its security-threshold gate.

**Who this is for:** teams who run security scanners (Trivy, Brakeman, Gitleaks,
Grype, and anything the [SAF CLI](https://saf.mitre.org/) can convert to HDF) and
need a standardized, evidence-linked way to say "this finding is a false positive"
/ "risk accepted" / "tracked as a POA&M" — without hand-editing per-tool ignore
files and losing the audit trail.

**What SPARC is here:** a translation engine and human-in-the-loop UI. Your
scanners, your CI, and your Authorizing Official remain the source of truth. SPARC
records each disposition as a re-derivable translation artefact — nothing is
trapped in SPARC that you can't reconstruct from your own inputs.

---

## Where it lives

Every triage flow is scoped to an **Authorization Boundary** (the system you're
assessing). Reach it three ways:

- The left **sidebar** — under each boundary, **Amendments** sits between **SSP**
  and **SAP**.
- The **Amendments** button on the boundary's page header.
- The **Amendments** button on any POA&M page (jumps to that POA&M's boundary).

Or go straight to `…/authorization_boundaries/<your-boundary>/triage`.

You need the `evidence.read` permission on the boundary to view triage, and
`evidence.write` to ingest scans or set dispositions. Approving an amendment is a
separate permission — see [Approval and validity](#approval-and-validity-809).

![The HDF Amendment Triage screen: an ingest form with Target/CDEF and Scope selectors, a recent-scan-runs panel, status/severity/lifecycle/target filters with an Include history toggle, and the findings table showing Component, Lifecycle, and Disposition columns alongside the Aggregate and Download Package actions.](images/hdf-triage.png)

---

## 1. Ingest a scan

1. Produce an HDF results file. Most scanners aren't HDF natively — convert with
   the SAF CLI, e.g. `saf convert trivy2hdf -i trivy.json -o scan.hdf.json`. A
   multi-scan bundle (a JSON array of HDF docs) is accepted too.
2. On the triage page, under **Ingest scanner output (HDF)**, choose the file.
   Set **Target / CDEF** and **Scope**, then click **Upload & Ingest**.

### Tie a scan to what it assessed (#811)

Not every scanner covers the whole system. Trivy, Gitleaks, and secret scanners
assess a **specific component/target**; AWS Config (and other posture scanners)
are **boundary-wide**. So each ingest records:

- **Target / CDEF** — the component definition this scan assessed. Leave it
  *Boundary-wide (no CDEF)* for whole-system scans.
- **Scope** — `Target` (component-specific) or `Boundary` (system-wide).

This makes findings audit-ready: you can filter the board by target/CDEF, and an
amendment applies to the component it was assessed against.

### Scan history and re-occurrence lifecycle (#811)

Re-uploading a fresh scan does **not** overwrite the last one. SPARC keeps every
scan run and marks each finding with a **lifecycle status** relative to the prior
current scan:

| Lifecycle | Meaning |
|---|---|
| **New** | First time this control failed |
| **Carried forward** | Still failing, same or lower severity, already dispositioned |
| **Re-failed** | Failing again at a **worse** severity than before — needs review |
| **Expired** | A prior disposition's validity window (ODP / waiver) has lapsed |
| **Superseded** | An older scan's row, kept for the audit trail |

The board shows the **current** scan by default. Tick **Include history** to see
superseded rows. A red banner flags any **re-failed** findings — the ones most
likely to need a fresh decision. Your existing disposition on a control is
preserved across re-scans.

The **Recent scan runs** panel shows the last few ingests with each run's
target/CDEF, scope, and failed count.

---

## 2. Triage the findings

The **Findings** table lists every control. Filter by **status** (start with
`failed` — that's your worklist) and **severity**. For each finding, click
**Disposition** to record a decision.

### Override kinds

Pick the override that matches reality. Each links to a supporting record so the
decision carries provenance:

| Kind | Meaning | Links to | Amended status |
|---|---|---|---|
| `falsePositive` | The scanner is wrong / the code path isn't reachable | an **Evidence** record justifying it | Not Applicable |
| `waiver` | Risk formally accepted | an **Attestation** by an *Authorizing Official* (+ expiration) | Not Applicable |
| `poam` | Real, tracked, will be fixed | an existing **POA&M finding** | Failed (tracked) |
| `vendorDependency` | Upstream/vendor issue tracked as a POA&M | an existing **POA&M finding** | Failed (tracked) |
| `inherited` | Provided by an upstream system | the upstream **Authorization Boundary** | Not Applicable |
| `riskAdjustment` | Severity downgraded with rationale | a **Risk Assessment** record | Failed (adjusted) |
| `operationalRequirement` | Can't fix; business need | an **Attestation** by an *Authorizing Official* (+ expiration) | Failed |

To link a supporting record, enter its **type** (e.g. `Evidence`, `PoamFinding`,
`Attestation`, `AuthorizationBoundary`, `RiskAssessment`) and its **id**, add a
**justification**, and — for `waiver` / `operationalRequirement` — an
**expiration** date. Save.

The form updates a hint showing which record type the selected kind requires.

### Rules SPARC enforces

- **Critical findings cannot be waived, downgraded, or marked operational.** A
  CRITICAL must be remediated or tracked as a POA&M. `falsePositive` is still
  allowed on a critical (the scanner can be wrong).
- **Waivers and operational requirements need an Authorizing Official
  attestation and an expiration** — no open-ended risk acceptance.
- One active disposition per finding. Re-dispositioning replaces the prior one.

Clear a disposition any time with **Clear** next to its badge.

### Approval and validity (#809)

A disposition is a proposed **amendment**. It only suppresses a finding once it is
**approved** *and* still within its **validity window**:

- **Approval.** A new disposition starts as `draft`. An approver (an Instance
  Admin, or any role the Admin has granted the `amendment.approve` permission)
  clicks **Approve** (or **Reject**) on the disposition. The amendment records
  both the person who decided it and the person who approved it. Until approved, a
  disposition does **not** suppress its finding in aggregation or the signed
  package.
- **Validity window (ODP).** SPARC computes how long an amendment stays valid
  from the **Organization-Defined Parameter (ODP)** in the profile your boundary
  uses for remediation timelines. Absent a profile ODP, it falls back to the
  admin **Remediation Timelines** table — a grid of *baseline* (Low / Moderate /
  High) × *NIST criticality* (Critical / High / Moderate / Low / Informational /
  Unknown) → **days**. The window runs from the finding's first-discovered date.
  An amendment backed by an **active POA&M** for the control has no expiry (the
  POA&M is the tracking mechanism).

Once the window lapses, the finding returns to the board as **Expired** and must
be re-decided. Instance Admins provision the fallback table under
**Admin → Remediation Timelines**. The grid ships with sensible defaults — set it
to your organization's actual remediation policy, because these values decide how
long an amendment keeps suppressing a finding.

![Admin → Remediation Timelines: a grid of remediation days with a row per profile baseline (Low, Moderate, High) and a column per NIST criticality (Critical, High, Moderate, Low, Informational, Unknown), each cell an editable day count with its own Save button.](images/remediation-timelines.png)

---

## 3. Export amendments for your pipeline

Click **Download Amendments** to get an HDF Amendments JSON document containing
one override per current, non-expired disposition. Feed it to your pipeline:

```bash
hdf amend apply --results scan.hdf.json --amendments boundary-amendments.hdf.json -o amended.hdf.json
saf validate threshold -i amended.hdf.json -F threshold.yml
```

`hdf amend apply` sets each control's `effectiveStatus` from your dispositions, so
your threshold gate sees false positives and waivers suppressed and POA&Ms tracked
— exactly as you triaged them.

The export is **deterministic**: the same dispositions always produce the same
document (stable ordering + a content-derived id), so you can safely cache the
artefact in your pipeline. A control that no longer appears in your latest scan
(remediated) automatically drops from the export.

---

## 4. Aggregate findings into your ATO documents (#809)

Scanner evidence belongs in the boundary's assessment documents, not just the
triage board. Click **Aggregate into documents** to fold the current findings and
approved amendments into this boundary's **SSP**, **SAP**, **SAR**, and **POA&M**:

- Each finding is mapped to the NIST control(s) it carries in its HDF `tags.nist`,
  and a non-destructive `hdf_scan_result` annotation is written on the matching
  SSP/SAP/SAR control — your authored narrative is never overwritten.
- Failed findings without an approved, in-window suppression become **POA&M**
  items (`HDF: <control-id>`), so open risk is tracked automatically.
- Suppressed findings (approved false positives / waivers within validity) are
  skipped.

You get a per-document summary of how many controls were touched. Over the API the
same action can run asynchronously (`?async=true`) as a background job for large
boundaries.

## 5. Download the signed package (#809)

Click **Download Package** for a single, **HMAC-SHA256 signed** bundle —
amendments + a findings summary + a dispositions summary — that a consumer can
archive or feed downstream. The signature is derived from this instance's
`SPARC_HASH`, so the bundle is tamper-evident and provably from your SPARC
instance (the same signing pattern as federation bundles). Verify it with the
`signature` / `encoded_payload` fields the bundle carries.

---

## Automating it (API)

Everything above is available over the REST API for CI, scoped per boundary by an
API token:

| Action | Endpoint |
|---|---|
| Ingest a scan (with `cdef_document_id`, `scanner_scope`) | `POST /api/v1/authorization_boundaries/:id/scan_runs` |
| List findings (current by default; `include_history=true`, `lifecycle=…`, `cdef_document_id=…`) | `GET /api/v1/authorization_boundaries/:id/scanner_findings?status=failed` |
| Set a disposition | `POST /api/v1/scanner_findings/:uuid/disposition` |
| Approve / reject an amendment | `POST /api/v1/scanner_findings/:uuid/disposition/approve` · `…/reject` |
| Aggregate into SSP/SAP/SAR/POA&M (`?async=true` to enqueue) | `POST /api/v1/authorization_boundaries/:id/aggregate` |
| Export amendments | `GET /api/v1/authorization_boundaries/:id/hdf_amendments` |
| Download the signed package | `GET /api/v1/authorization_boundaries/:id/hdf_package` |
| Remediation timelines (admin) | `GET` / `PUT /api/v1/admin/remediation_timelines` |

The export endpoint validates its own output with `hdf amend verify` before
returning, so a schema drift surfaces as an error rather than a bad artefact.
Approve/reject and aggregate require `evidence.write` on the boundary; approving an
amendment additionally requires admin or the `amendment.approve` permission.

---

## Related

- [Evidence & Attestations](User-Guide-Evidence-and-Attestations) — the records
  that back `falsePositive` and `waiver` dispositions.
- [POA&M](User-Guide-POAM) — the tracker `poam` / `vendorDependency` link to.
- [Authorization Boundaries](User-Guide-Authorization-Boundaries) — the scope for
  all triage.
