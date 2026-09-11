# Onboarding a Team and a Pipeline

_The path from "we have a SPARC instance" to "our evidence is landing against
controls." For single-operator local setup see [Getting Started](Getting-Started);
for the catalogue of what SPARC connects to see [Integrations](Integrations)._

There are two tracks, and they are independent. **People** sign in and hold
roles. **Pipelines** authenticate as service accounts and push artifacts. Most
adopters need both, and the single most common failure is configuring SPARC so
that only one of them can work.

---

## 1. Prerequisites — build the estate first

SPARC **never creates an organization, authorization boundary or role on your
behalf.** A grant naming something that does not exist is recorded and surfaced
to an administrator, never auto-provisioned — otherwise your directory could
define your estate.

Create these, in order, before anyone signs in expecting access:

1. **Organization** — the tenant.
2. **Authorization Boundary** — the system being authorized. Note its **slug**;
   it appears in the boundary's own URL (`/authorization_boundaries/<slug>`) and
   it is what group names must match.
3. **Roles** — seeded already; see [RBAC](RBAC) for the 30 that ship.

> A user who signs in before the boundary exists lands in an empty SPARC with no
> explanation. The access resolves by itself at their **next** sign-in once you
> create it — nothing needs re-issuing.

---

## 2. Choose the API authentication mode

`SPARC_API_AUTH` decides what the API accepts. It defaults to `local`.

| Mode | Accepts | Use when |
|------|---------|----------|
| `local` *(default)* | SPARC API tokens (`sparc_…`) only | No IdP, or humans do not call the API |
| `oidc` | OIDC JWTs only, validated via JWKS | Humans call the API and you have no automation |
| `hybrid` | JWTs for people **and** SPARC tokens for service accounts | **Both tracks — the usual answer** |

> **This is the quiet failure.** In `oidc` mode a perfectly valid service-account
> token is rejected, so *every* pipeline call fails identically no matter what
> token you present — which reads as "our token is wrong" and sends people to
> re-issue credentials that were never the problem. If you have a pipeline and an
> IdP, you want `hybrid`.

---

## 3. Track A — people

SPARC can read role grants from an IdP claim, so membership is managed where your
people already are. See [Integrations](Integrations#group-based-entitlements-letting-the-idp-decide-who-holds-which-role)
for the full configuration; the essentials:

**Group naming.** A grant is a group name:

```
sparc:instance:{role}
sparc:org:{org_slug}:{role}
sparc:boundary:{org_slug}:{boundary_slug}:{role}
```

Use the **slug**, not the display name. A boundary called `Café & Co — Prod` has
the slug `cafe-co-prod`.

**Adopt in order.** `SPARC_OIDC_SYNC_MODE` goes `off` → `bootstrap` (adds grants,
never removes) → `authoritative` (adds and removes). `off` → `authoritative` is a
cliff.

**Rights are established at login.** SPARC resolves entitlements when a person
signs in, and learns of directory changes at their next sign-in.
`SPARC_SESSION_MAX_HOURS` bounds a session already open, so a change is not
waiting on someone to go idle.

### Two failures that look like something else

- **A grant naming nothing.** The login still succeeds, so nobody notices until
  someone asks why they cannot see a boundary. It surfaces under
  **Administration → IdP Grants**, with a daily digest when SMTP is configured.
- **Local login left enabled for a person.** If someone also holds a local
  password, disabling them at the IdP is **not a complete offboard**. Either
  disable local login instance-wide, or deactivate the account in SPARC as well.

---

## 4. Track B — the pipeline

**Create a service account**, not a human account with a shared password. Service
accounts are exempt from the interactive auth gates (MFA, required-method
policies) precisely because they have no human to prompt.

Their tokens carry a distinct prefix — **`sparc_sa_`** — so they are
identifiable in logs and in an audit review.

**Scope the token.** An API token supports:

| Constraint | Effect |
|---|---|
| `allowed_endpoints` | The token may call only these endpoints |
| `allowed_cidrs` | The token is refused from outside these ranges |
| `expires_at` | The token stops working, whether or not anyone remembers |
| `scopes` | Per-permission limits |

A CI token that can only POST scan results from your runner's egress range is a
much smaller thing to lose than an unscoped one.

**Store it as a CI secret**, never in the repository.

---

## 5. Modelling the boundary

Before pushing anything, decide what the boundary *is*:

- **Leveraged** — what you inherit from a provider (the CSP's controls). You do
  not evidence these; you reference them.
- **Shared** — responsibility is split. Both parties evidence their half, and the
  split has to be stated.
- **System-specific** — yours alone, and yours to evidence.

A component needs a **CDEF** when it makes a control claim you want to reuse
across boundaries. One that implements nothing you will claim does not.

> The leveraged/shared/system-specific modelling rules and the inheritance
> examples live in [`risk-sentinel/sparc-iac`](https://github.com/risk-sentinel/sparc-iac)
> (`docs/CDEF_Guide.md`, `oscal/inheritance/`). They are the authority; this page
> only names the distinction so the endpoints below make sense.

---

## 6. What the pipeline pushes

Verified against `bin/rails routes`, not against prose:

| Purpose | Endpoint |
|---|---|
| **Scanner results (HDF)** | `POST /api/v1/authorization_boundaries/:authorization_boundary_id/scan_runs` |
| Evidence artifacts | `POST /api/v1/evidences` |
| Attest to a piece of evidence | `POST /api/v1/evidences/:evidence_id/attestations` |
| Link evidence to controls | `POST /api/v1/evidences/:evidence_id/control_links` |
| Component definitions | `POST /api/v1/cdef_documents` |
| HDF → OSCAL Assessment Results | `POST /api/v1/oscal/sar_from_hdf` |
| HDF → OSCAL POA&M | `POST /api/v1/oscal/poam_from_hdf` |
| Convert an SAR document | `POST /api/v1/sar_documents/convert` |

> **Scanner findings are not created directly.** `/api/v1/scanner_findings` is
> **read-only** — it serves findings and their dispositions. Findings come into
> existence by ingesting an HDF file at the `scan_runs` endpoint above, which
> creates the run and its findings together. Posting to `scanner_findings`
> expecting ingestion will fail, and the shape of the failure will not tell you
> why.

The `scan_runs` call accepts an optional `cdef_document_id` (attributing the run
to a component) and `scanner_scope` (defaults to `target`).

---

## 7. Verify, and make failure loud

Confirm the integration end to end:

1. **A person** signs in via the IdP and sees the boundary they were granted.
2. **Check the unmatched-grant queue** is empty — **Administration → IdP Grants**.
3. **The pipeline** pushes a scan run and receives `201 Created`.
4. The findings appear under the boundary's triage screen.

> **Assert the status code in CI.** A push that never fails the build lets a
> broken integration look healthy indefinitely — the job is green, nothing has
> landed for weeks, and the first person to notice is an assessor. A bare
> `curl` without `--fail` is the usual culprit.

### Failure modes, and what each actually means

| Symptom | Cause |
|---|---|
| Every API call 401s, regardless of token | `SPARC_API_AUTH=oidc` with a service-account token — use `hybrid` |
| A person signs in but sees nothing | The grant named an org/boundary/role that does not exist; check **IdP Grants** |
| 403 from one endpoint only | The token's `allowed_endpoints` does not include it |
| 403 from CI but not from a laptop | `allowed_cidrs` does not cover the runner's egress |
| Worked yesterday, 401 today | The token's `expires_at` passed |
| Offboarded at the IdP, still signing in | They hold a local password as well |

---

## Related

- [Integrations](Integrations) — the IdP, storage and deployment catalogue
- [RBAC](RBAC) — roles, permissions, and the two administrative authorities
- [Authentication and MFA](Authentication-and-MFA) — phishing-resistant methods
- [API Reference](API-Reference)
