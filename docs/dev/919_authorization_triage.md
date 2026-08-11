# #919 — controller authorization triage

**Status: memo. No fixes in this commit.** Two decisions are owed before the fix
commits land — see [Decisions required](#decisions-required).

Derived by reading each controller, not by pattern-matching for guard names. That
distinction matters: a first pass grepping for `authorize_*` reported
`leveraged_authorizations` as unguarded when it is in fact *differently* guarded,
and the same shortcut would have mis-scored `require_admin`.

---

## Part 1 — the permission vocabulary

`Role::PERMISSION_KEYS` defines **35** keys. Measured against the seeded 29-role
catalog, the code that enforces them, and `wiki/RBAC.md`:

| Category | Count | Meaning |
|---|---|---|
| Healthy — granted, enforced, documented | 22 | working as intended |
| **Enforced, granted to nobody** | **11** | admin-only in practice, by accident |
| **Granted, enforced by nothing** | **1** | `converters.read` — 7 roles hold a permission no code checks |
| **Dead — neither granted nor enforced** | **1** | `authorization_boundaries.manage_members` |

**13 of 35 keys (37%) are anomalous.** The issue anticipated one
(`manage_members`) and suspected a second (`authorization_boundaries.write`).
The real figure is thirteen, which changes the character of the problem: this is
not an orphaned key, it is a **systemic seeding gap**.

### Enforced but granted to no role (11)

```
admin.rotate_credentials          catalogs.approve
authorization_boundaries.write    cdef.approve
back_matter.approve_promotion     converters.write
back_matter.archive               profiles.approve
back_matter.bulk_import
back_matter.federate
back_matter.promote
back_matter.write
```

Because `User#has_permission?` returns true for `admin?`, every one of these is
**instance-admin-only on a stock instance**. Nobody decided that; it fell out of
the seeds never granting them.

The `back_matter.*` cluster is the clearest illustration: `back_matter.read` is
granted to 7 roles, while **write, promote, archive, federate, bulk_import and
approve_promotion are granted to zero**. The entire back-matter authoring and
promotion workflow — a headline feature — is admin-only out of the box. The same
shape repeats in the `*.approve` keys: catalogs, cdef and profiles all define an
approval permission that no role holds, so the #630–#634 approval workflow is
also admin-only unless an operator grants it by hand.

### Granted but enforced by nothing (1)

`converters.read` is held by 7 roles and checked by no code. Either the converter
screens should enforce it, or the key should go — but a permission that grants
nothing is worse than no permission, because the role catalog implies an access
boundary that does not exist.

### Dead (1)

`authorization_boundaries.manage_members` — granted to 0 roles, enforced by 0
code, and **documented in `wiki/RBAC.md:75`** as "Add / remove members and assign
roles within a boundary". The published RBAC documentation describes a capability
the application does not implement. This is the one the issue named.

---

## Part 2 — controller verdicts

### The defence that does not hold

Several of these are nested resources, and the natural assumption is that the
parent association scopes them. **It does not.** Every controller below loads its
parent with an *unscoped* lookup:

```ruby
@poam_document = PoamDocument.find_by!(slug: params[:poam_document_id])   # global
@poam_risk     = @poam_document.poam_risks.find(params[:id])              # scoped to that parent
```

The second line gives **referential integrity**, not authorization. Knowing the
parent's slug is sufficient. Compare `EvidencesController`, which uses
`boundary_scoped_relation(Evidence)` — that is the scoped pattern, and none of the
controllers below use it.

### Verdicts

| Controller | Guard today | Parent lookup | Verdict | Reachable impact |
|---|---|---|---|---|
| `attestations` | none | `Evidence.find_by!(slug:)` unscoped | **GAP** | Attest to / retract attestation on any evidence record whose slug is known — corrupts the assessor trail |
| `back_matter_resources` | `require_draft` (state, not authz) | `klass.find_by!(slug:)` unscoped | **GAP** | Add/alter/remove back-matter on any document. API sibling enforces **6** distinct permissions here; web enforces none |
| `boundaries` | none | `AuthorizationBoundary.find_by!(slug:)` unscoped | **GAP** | Edit boundary environments on any boundary — the exact shape of the #918 roster bug |
| `control_back_matter_links` | none | `BackMatterResource.find(id)` + `klass.find(id)`, both unscoped | **GAP** | Link any resource to any control across documents — cross-document injection |
| `poam_findings` | none | `PoamDocument.find_by!(slug:)` unscoped | **GAP** | Tamper with POA&M findings on any boundary |
| `poam_items` | none | same | **GAP** | Tamper with POA&M items |
| `poam_local_components` | none | same | **GAP** | Tamper with POA&M components |
| `poam_milestones` | none | same, two levels deep | **GAP** | Alter remediation milestones — the dates an AO relies on |
| `poam_observations` | none | same | **GAP** | Tamper with observations |
| `poam_remediations` | none | same | **GAP** | Alter remediation plans |
| `poam_risks` | none | same | **GAP** | Alter risk records. API sibling enforces `poam.read`/`poam.write` — template transfers directly |
| `profile_controls` | none | `ProfileDocument.find_by!(slug:)` unscoped | **GAP** | Edit a baseline's controls — a profile's controls *are* the profile |
| `profile_documents` | `ensure_editable!` (state), `require_authentication_unless_public_controls` (authN) | `find_by!(slug:)` unscoped | **GAP** | Mutate any profile. Its own API sibling carries a comment noting the web side has no gate |
| `promotion_queue` | none on `approve`/`reject` | `BackMatterResource.find(id)` unscoped | **NEEDS CONFIRMATION** | `index` self-filters per record via `can_approve?`; must confirm `approve!`/`reject!` re-check at the service layer before scoring |
| `federation_peers` | `require_admin` (hand-rolled) | `FederationPeer.find` (global resource) | **DIVERGENT** | Not a hole. Web is admin-only; API enforces `back_matter.federate`. The two surfaces disagree, and `require_admin` should be `authorize_admin!` |
| `leveraged_authorizations` | `authorize_leveraging_boundary` (hand-rolled) | scoped to `@leveraging_boundary` | **NON-CANONICAL** | Guarded, but bypasses `authorize_permission!` — so it emits **no `authorization_failure` audit event** and ignores `SparcConfig.any_auth_enabled?`. Membership is also not the same as write permission |

**13 real gaps, 1 needing confirmation, 2 guarded-but-inconsistent.**

Common thread across the 13: the compliance record — POA&M content, profile
baselines, back-matter provenance, attestations — is editable by any authenticated
user who knows a slug. As with #918, this is an **integrity and audit-trail**
problem rather than data exfiltration; document *reads* remain gated by
`user_roles` → `Role#permissions`.

---

## Decisions — DECIDED 2026-08-11 (owner)

Settled. Recorded here so they are not re-opened; the questions that produced
them are kept below for the reasoning.

### 1. Roster posture → **delegable**

Seed `authorization_boundaries.manage_members` onto **issm, isso, so_iso** and
switch both the web and `Api::V1` surfaces to enforce it. `wiki/RBAC.md:75`
already describes this behaviour, so the documentation becomes true rather than
being corrected downward. `authorization_boundaries.write` is seeded to the same
three.

### 2. Back-matter is **not** admin-only

Two tiers, by what the resource pertains to:

- **Instance-level back-matter** (globally available / authoritative) →
  **policy team + instance-level roles**, plus instance admin.
- **Boundary-scoped back-matter** → **members of that boundary**, excluding
  `assessor_3pao` (separation of duties — an assessor must not edit the
  provenance they are assessing) and `view_only`.

**The boundary set is the 14 roles that already hold some document write**, not
all 17 non-excluded roles. `ciso`, `information_owner_steward` and
`solution_evaluator` are excluded as well: they write no document today, and
granting them back-matter authority would give them more control over compliance
artifacts than over the documents those artifacts support. This follows the
governing rule — *the ability to manage documents matches the RBAC already
decided*.

```
ao  agency_ao  cloud_service_provider  common_control_provider
component_supplier  evidence_integration_engineer  issm  isso
project_member  so_iso  sparc_sme  system_architect_engineer
system_operator_admin  vendor_dependency_manager
```

Applies to `back_matter.write`, `.promote`, `.archive`, `.bulk_import`,
`.federate`, `.approve_promotion` and `converters.write`.

### 3. Approval keys

- `catalogs.approve`, `profiles.approve` → **policy_manager** (it already holds
  `catalogs.write` / `profiles.write`).
- `cdef.approve` → **issm, isso, so_iso _and_ the policy team** — CDEF approval is
  not purely a boundary concern.

### 4. `admin.rotate_credentials` stays instance-admin-only

Correct as-is. Pinned by a spec so it stops reading as an oversight.

### 5. `converters.read` → **removed**

Any authenticated user may read converters, so the current behaviour — no check —
is right. The key is therefore redundant: it is granted to 7 roles and implies an
access boundary that does not exist, which is worse than no key at all. Remove it
from `Role::PERMISSION_KEYS`, from the seeds, and from `wiki/RBAC.md`; existing
JSONB entries on stored roles become inert and harmless.

---

## Decisions required *(kept for reasoning — settled above)*

### 1. Boundary-roster posture

v1.15.5 fixed the roster hole with `authorization_boundaries.write`, which is
granted to **no role** — so roster management is instance-admin-only today.

- **(a) Admit admin-only.** Delete `manage_members`, correct `wiki/RBAC.md` to
  describe what is enforced. Cheapest, and matches current behaviour.
- **(b) Make it delegable.** Seed `manage_members` onto ISSM/ISSO/SO and switch
  both surfaces to it. Matches what the documentation already promises.

Note this cannot be settled in isolation: `authorization_boundaries.write` is one
of the 11 enforced-but-ungranted keys, so whichever way it goes, the seeding
question below applies to the same cluster.

### 2. The 11 enforced-but-ungranted keys

Is admin-only the intended posture for back-matter authoring, promotion,
federation, and catalog/cdef/profile approval — or is this a seeding gap?

- **(a) Intended.** Document it, and add a spec pinning "these keys are
  deliberately admin-only" so it stops looking like an accident.
- **(b) Gap.** Seed them onto the appropriate roles. Larger change, touches
  `db/seeds/roles.rb` and requires a `SeedRunner::CURRENT_VERSIONS` bump.

My recommendation is **(b) for the `back_matter.*` and `*.approve` clusters** —
a documented approval workflow that only an instance admin can exercise is not a
workflow — and **(a) for `admin.rotate_credentials`**, which is correctly
admin-only. But this is a product-posture call, not a code call.

---

## Planned work once decided

1. Close the 13 gaps, each mirroring its `Api::V1` counterpart's permission key so
   the two surfaces cannot drift.
2. Harmonize `federation_peers` and `leveraged_authorizations` onto
   `authorize_permission!` so denials are audited.
3. Confirm or fix `promotion_queue`.
4. **The deliverable that matters:** a structural spec enumerating every
   controller with mutating actions and asserting an unauthorized user is refused,
   with a justified allowlist for the genuinely public ones (`sessions`,
   `passwords`, `password_resets`, `registrations`, `omniauth_callbacks`,
   `piv_sessions`, `webauthn_sessions`, `webauthn_credentials`, `profiles`). A new
   controller without a guard then fails on arrival.
5. A second spec failing when a permission key is defined but never enforced, or
   documented in `wiki/RBAC.md` but granted to no role — so the 13 anomalies above
   cannot silently return.

Each fix gets a denial test that is mutation-checked, per
`spec/requests/authorization_boundary_memberships_authz_spec.rb`.

### Spec gotchas

- Guards no-op unless `SparcConfig.any_auth_enabled?` — the sweep spec must stub
  it true, or it passes against an unguarded app.
- Web denial is a **302 to root**, not a 403. Only JSON requests get 403.
- The positive control matters as much as the negative one: assert an admin can
  still perform each action, or an over-tight guard ships green.
