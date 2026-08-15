# The reference leveraged authorization estate (#845)

A complete, inspectable authorization chain for **two boundaries in a real
leveraging relationship**, loadable with one command.

Before this existed, anything that needed a realistic authorization — a demo, a
DAST run, a screenshot, a spec about cross-organization access — assembled its
own from disconnected fixtures. Each assembly invented its own idea of how the
documents relate, and the ones that got it wrong looked exactly like the ones
that got it right.

## What it builds

Two organizations, two boundaries, and the full chain on each side:

```
Org A — Reference Platform Provider          Org B — Reference Mission System Owner
  Boundary 1 (LEVERAGED / provider)            Boundary 2 (LEVERAGING / consumer)
    Catalog → Profile → SSP                      Catalog → Profile → SSP
                 ↓                                          ↑
                SAP                            inheritance links (per statement)
                 ↓
                SAR  →  3 POA&Ms  +  Evidence
```

Boundary 1 declares, per statement, what it **provides** to its customers and
what it hands **back** to them:

- `provided` — pe-3, sc-7, au-9, cp-9, ma-2. Genuinely platform-level: physical
  access, boundary protection, audit storage, backups, maintenance.
- `responsibility` — sa-9, ac-20, ia-5. The external-services pair plus
  authenticator management, which is exactly the seam a leveraging system has to
  address itself.

Boundary 2 inherits prose for the first set and gets an empty statement to author
for the second. A responsibility is the *opposite* of an inherited
implementation, and treating them alike was #956.

## Tiers

| Tier | Controls per boundary | Notes |
| --- | --- | --- |
| `lean` | 40 curated, spanning all 20 families | The default, and what the suite uses |
| `full` | Real NIST baselines — MODERATE (287) provider, LOW (149) consumer | Demos and scale checks |

The provider gets the **higher** baseline. MODERATE is a strict superset of LOW
(0 absent, 138 added), so every consumer control has a provider counterpart to
inherit from. Reversed — which is how this was first written — 138 controls have
nowhere to inherit from and the fixture silently understates the relationship.
A spec pins consumer ⊆ provider so it cannot flip back.

Both tiers use the **same organization and boundary names**. There is one
reference estate, not one per tier, so loading a different tier replaces the
current one.

## Realism

Satisfaction is **derived from evidence**, not assigned. That is the product's
actual proposition: a control is satisfied because something demonstrated it,
and you can click through to what that was.

- Technical families are covered by three simulated scanners with disjoint
  family ownership — `checkov` (IaC: cm, sc, sa, cp), `aws-config` (cloud
  posture: ac, au, ra) and `inspec` (host baseline: ia, si, pe, ma, mp).
- Management and policy families — and every `-1`, which is "Policy and
  Procedures" by definition — are covered by documents a policy team publishes.
  No scanner can assess whether an organization wrote and disseminated a policy.
- A control with **no** covering evidence is never marked satisfied. An earlier
  version computed `passed = technical − failed`, which quietly satisfied every
  control no scanner touched.

The result is ~95% satisfied / ~5% open, and the open ones become SAR risks,
which become POA&M items. Each boundary gets three POA&Ms — Initial (published),
Current (in progress) and Overdue — because a POA&M screen with one row in one
state exercises almost nothing.

## Commands

```bash
bin/rails db:seed:reference                 # lean tier
bin/rails 'db:seed:reference[full]'         # real NIST baselines
bin/rails db:seed:reference:status          # what is currently loaded
bin/rails db:seed:reference:purge           # remove it
bin/rails 'db:seed:reference:regenerate[lean]'  # rewrite the committed OSCAL
bin/rails 'db:seed:reference:check[lean]'       # fail if the OSCAL has drifted
```

Or as part of `db:seed`:

```bash
SPARC_SEED_REFERENCE=lean bin/rails db:seed
```

The tier is folded into the recorded seed version (`1.0.0+lean`), so a database
seeded at `lean` is correctly **not** considered seeded when the operator asks
for `full`. Without that, `SeedRunner` would skip the section and leave the wrong
estate in place.

Every entry point refuses to run in production. A reference estate is
indistinguishable from real authorization data once it is in a database.

## Committed OSCAL artifacts

`db/fixtures/reference/<tier>/*.json` holds the estate exported through the
**validated** OSCAL path. They exist so consumers can read a complete, valid
authorization without a database — and so regeneration is a drift gate:
`db:seed:reference:check` rebuilds into memory and compares byte-for-byte.

Byte-identical regeneration required pinning everything time- or
sequence-dependent. Twelve artifacts drifted on the first attempt. The causes,
because each will come back if someone unpins one:

- `metadata.last-modified`, read from each record's `updated_at`
- `SarResult#start_time`, and any SLA-derived deadline (`Time.current`-relative)
- `sparc_resource_uuid`, which the exporter used to mint during export
- the SSP `system_id`, which leaked the database primary key
- components, users, info-types and `by-components`, all unordered
- the `LeveragedAuthorization`, and evidence `BackMatterResource` uuid *and*
  stored `href`
- five unordered queries in the SAP, SAR, POA&M and back-matter exporters

**Regenerate only from a clean, freshly seeded database.** Instance-level
authoritative back-matter is embedded in every export regardless of relevance
(#959), so regenerating from a working database bakes unrelated resources into
the artifacts — 96 leftover ui-smoke resources, the first time this ran.
`regenerate!` now refuses and names them rather than committing them.

## Using it in specs

```ruby
estate   = reference_estate(:lean)
provider = estate.leveraged      # Boundary 1 — provides
consumer = estate.leveraging     # Boundary 2 — consumes

provider[:ssp]    # SspDocument, 40 controls with statements
provider[:poams]  # 3 PoamDocuments
```

`spec/support/reference_estate_helper.rb` synthesises its own catalog rather
than reading whatever the database happens to hold, so the estate is the same
shape on a fresh checkout as on a developer machine with three seeded catalogs.

Two traps, both of which produced examples that passed without testing anything:

- **`estate` is a lazy `let`.** An example that names it only inside its
  assertion builds the estate *after* the response is rendered. Force it in a
  `before` block. This hid one example from a mutation that removed boundary
  scoping from the index entirely.
- **Every POA&M name contains an ampersand.** Compare against `html_text(name)`,
  not the raw string — see `spec/support/html_escaping_helpers.rb`.

## Isolation

`spec/requests/reference_estate_isolation_spec.rb` pins the property the estate
exists to demonstrate: a leveraging relationship grants a view of what the
provider *declared it provides*, and nothing else. Org B must not reach Org A's
SSP, SAP, SAR or POA&Ms — the documents that say where Org A is weak.

It asserts in both directions across both the controller and API paths, and has
the provider's own member read everything the consumer was refused, so the
isolation cannot be an artefact of the estate failing to build.

## Related issues

| Issue | What it was |
| --- | --- |
| #954 | SAR findings never became risks, so generated POA&Ms were empty |
| #955 | Profile-generated SSPs arrived with no control statements |
| #956 | Customer responsibilities were reported inverted in both directions |
| #957 | Generators still mint random UUIDs (open, v1.16.0) |
| #958 | Leveraged SSPs were not exportable; exports were not reproducible |
| #959 | Instance-level back-matter is embedded unscoped in every export (open) |

The pattern running through #954, #955 and #958: **building an authorization
inside SPARC was hollow where importing one was complete.** The import paths
populated relationships the generators skipped, so a document that arrived by
import worked and the same document built in the UI did not.
