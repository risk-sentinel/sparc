# Adopting OSCAL with SPARC

_For a boundary moving from static documentation — Word, Excel, a slide deck, a
proprietary GRC tool — to OSCAL. This page is the set of **decisions** you make
on the way in, and what SPARC needs from each one._

It is deliberately not a form to fill in. The goal is to reach the point where
adopting OSCAL is the obvious next step rather than a leap, and that depends far
more on decisions you make **before** any document exists than on the document
itself.

Two layers are in play throughout, and confusing them is the most common way an
adoption stalls:

- **Implementation** — what your system *is*, and what you claim it does.
  Components, ports and protocols, inherited controls, narratives.
- **Assessment** — what *demonstrates* the claim. Scan results, evidence,
  findings, POA&M items.

A boundary that models implementation without a plan for assessment produces a
package that validates and proves nothing. The reverse produces evidence that
maps to no claim.

---

## 1. Who is on the team, and what are their roles?

**Decide first. A boundary with no Authorizing Official is not one anyone can
act on**, and this is what later populates OSCAL `responsible-parties` — so a
roster assembled late means a package that cannot name who is accountable.

| You need | Where it lands |
|---|---|
| System Owner, ISSO, Authorizing Official at minimum | Boundary personnel roster (`AuthorizationBoundaryMembership`) |
| Everyone else who will act in SPARC | Same roster; org-level rights via `OrganizationMembership` |

Roles can come from your IdP rather than being maintained by hand — see
[Onboarding a Team and a Pipeline](Onboarding-a-Team-and-a-Pipeline). Decide
**now** whether the directory or SPARC is the system of record for membership;
switching later means reconciling two rosters.

> SPARC has **two role systems** — organization membership and
> authorization-boundary membership. They answer different questions. See
> [RBAC](RBAC).

---

## 2. What makes up the boundary?

The inventory question, and the one teams most often arrive with only as a
diagram.

| You need | Where it lands |
|---|---|
| Components — what the system is made of | `SspComponent`, typed against the OSCAL component vocabulary |
| **Ports and protocols** (PPSM) | `SspComponent#protocols_data` |
| What each component is *for* | `SspComponent#purpose` |
| Operational status of each | `SspComponent#status_state` |
| Network and dataflow diagrams | Back-matter resources (see §4) |

> **Diagrams are back-matter, not inventory.** A network diagram registered as a
> back-matter resource is referenceable from the SSP; it is not a substitute for
> naming the components. If the only place a component appears is a PNG, OSCAL
> cannot say anything about it and neither can an assessor.

**Component type matters more than it looks.** OSCAL distinguishes `this-system`
from `software`, `hardware`, `service`, `policy`, `process-procedure`, `plan`,
`guidance`, `validation` and `interconnection`. Typing everything as
`this-system` is the path of least resistance and it costs you the ability to
say what is inherited, what is shared, and what you operate.

---

## 3. What is the classification?

| You need | Where it lands |
|---|---|
| FIPS-199 categorization (confidentiality / integrity / availability) | `SspDocument#security_sensitivity_level` |
| SP 800-60 information types | **Not modelled structurally today** — record in document metadata |
| The baseline that follows from it | Profile bound to the boundary (`AuthorizationBoundary#profile_document`) |

The categorization drives the baseline, and the baseline drives every control
you will have to answer for. Getting it wrong is expensive in both directions —
too high and you evidence controls that do not apply, too low and the package
fails review.

> Categorization lives on the **SSP**, not on the boundary, so it is recorded
> when the SSP is created rather than at intake.

---

## 4. Which documents become back-matter?

Everything an assessor would ask to see, registered **before** profile
resolution:

- Boundary definition / system description
- Network diagram, dataflow diagram
- Inventory
- PPSM registration
- CRM (customer responsibility matrix)
- Policies and procedures you cite

They land as back-matter resources with a `media_type` and, where relevant, a
`crm_type`.

> **Register before you resolve.** A profile that resolves while carrying
> dangling back-matter references produces an export that looks complete and
> cites documents nobody registered — the failure is invisible until someone
> follows a link.

---

## 5. Do you already have an SSP?

This is the fork that decides your whole route. SPARC models it explicitly as
`SspDocument#creation_method`:

| Your situation | Route | `creation_method` |
|---|---|---|
| A system exists; documentation does not, or is a slide deck | **Greenfield** — author in SPARC | `wizard`, `profile` |
| An ATO package exists as prose documents | **Brownfield** — transcribe deliberately | `oscal_import` |
| OSCAL already exists from elsewhere | **Brownfield** — import it | `oscal_import` |

Both converge on the same object graph. They differ in where content comes from
and **in the mistake each is prone to**:

- **Greenfield's risk is a thin SSP that validates.** Schema-valid and
  substantively empty is the easiest thing to produce and the hardest to notice.
- **Brownfield's risk is faithful transcription of a structure OSCAL does not
  share.** A team that spends a week mapping Word headings onto
  `system-characteristics` concludes OSCAL is a worse Word — and they are right,
  if that is what they were asked to do. Transcribe the *claims*, not the
  document's shape.

---

## 6. What are you leveraging?

Almost nothing is authorized alone. Decide explicitly what you inherit, because
an unstated inheritance reads as an unimplemented control.

| You need | Where it lands |
|---|---|
| The authorizations you leverage (CSP, platform, shared service) | `LeveragedAuthorization`, and the boundary's leveraged relationships |
| What each provides vs. what remains yours | CRM / `crm_type` |
| Component definitions for reusable claims | `CdefDocument` bound to the boundary |

Three categories, and every control belongs to exactly one:

- **Leveraged** — the provider implements and evidences it. You reference it.
- **Shared** — responsibility splits. Both sides evidence their half, and the
  split must be stated, not implied.
- **System-specific** — yours to implement and yours to evidence.

> A component needs a **CDEF** when it makes a control claim you want to reuse
> across boundaries. One that implements nothing you will claim does not.

---

## 7. Will you work through the UI or the API?

Both work; the decision is about who does the work and how often.

| | UI | API |
|---|---|---|
| Good for | Authoring narratives, review, one-off correction | Anything repeated, anything generated |
| Who | ISSO, System Owner, assessors | Pipelines, integrations |
| Cost | A person's time, every cycle | Set-up once |

**Every user-facing function in SPARC has an `Api::V1` endpoint** — the UI is a
thin client over the same endpoints. So this is not a one-way door: start in the
UI and automate later without re-modelling anything.

Decide the **API authentication mode now**, though, because getting it wrong
makes every automated call fail identically: `SPARC_API_AUTH=hybrid` is the mode
where human SSO and service-account automation both work. See
[Onboarding a Team and a Pipeline](Onboarding-a-Team-and-a-Pipeline#2-choose-the-api-authentication-mode).

---

## 8. How will you stay current?

The question that separates a package from a program. An SSP accurate on the day
it was authored and never again is the normal failure, not an unusual one.

| Approach | What it looks like |
|---|---|
| **Manual** | Someone edits in the UI on a cadence. Workable for a small, stable boundary; it degrades quietly |
| **API-assisted** | Inventory and components pushed from the source of truth; narratives authored by people |
| **Pipeline-integrated** | Scans, evidence and findings land automatically on every build; drift shows up as a failing check |

Whichever you choose, decide **what makes a change visible**. A new capability
should require a CDEF, a check, and evidence *together* — a capability with a
claim nobody evidences, or evidence that maps to no claim, is how a package
drifts while looking healthy.

---

## 9. How will you provide evidence?

The assessment layer. SPARC accepts several shapes, and they are not
interchangeable.

| Evidence | How it arrives | Notes |
|---|---|---|
| **Scan results (HDF)** | `POST /api/v1/authorization_boundaries/:id/scan_runs` | The native path. Becomes findings, mapped to controls via `tags.nist` |
| **OpenSCAP / SCAP** | Convert upstream: `saf convert xccdf_results2hdf`, then ingest as HDF | The converter resolves NIST controls itself |
| **CIS Benchmarks** | Convert upstream with `cis-bench`, then ingest | Same principle |
| **Documents, screenshots, logs** | `POST /api/v1/evidences` | Typed: `screenshot`, `log`, `artifact`, `scan_result`, `policy_document`, `signed_statement` |
| **Signed statements** | Evidence + attestation | For controls demonstrated by assertion rather than by artifact |

> **SPARC does not own scanner-to-NIST mapping, and should not.** Upstream tools
> resolve controls and emit the answer; SPARC reads it. Converting inside SPARC
> would mean maintaining mapping tables that MITRE already maintains better.

Link evidence to what it proves — `POST /api/v1/evidences/:id/control_links`.
**Unlinked evidence is a file, not evidence.**

---

## What "adopted" looks like

You are through when:

1. The roster names who is accountable, and OSCAL can say so.
2. Components exist as components — not only as a diagram — with ports and protocols.
3. The categorization is set and a baseline follows from it.
4. Back-matter is registered, and the profile resolves with no dangling references.
5. Every control is leveraged, shared, or system-specific — and says which.
6. The OSCAL package exports and validates.
7. Evidence is arriving on a cadence and is linked to controls.

Items 1–5 are the implementation layer, 6–7 the assessment layer. A package that
reaches 6 without 7 is a document; one that reaches 7 without 5 is a pile of
findings.

## Related

- [Onboarding a Team and a Pipeline](Onboarding-a-Team-and-a-Pipeline) — the mechanics of connecting
- [OSCAL End-to-End](OSCAL-End-to-End) — what the artifacts become
- [RBAC](RBAC) — roles and permissions
- [User Guide: Authorization Boundaries](User-Guide-Authorization-Boundaries) — the screens
