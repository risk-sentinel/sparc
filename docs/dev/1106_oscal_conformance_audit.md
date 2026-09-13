# #1106 — OSCAL conformance audit: props, namespaces and vocabularies

Pass 1 of the sweep: **every prop emitted by all eight exporters**, checked
against NIST's authority for OSCAL **v1.2.2**. Findings only — no fixes in this
commit, per the owner's direction to size the work before committing to it.

## Method, and what it can and cannot prove

Three sources, in descending order of authority:

1. **The NIST Metaschema for v1.2.2** (`src/metaschema/*.xml`), which is where
   `allowed-values` actually live. Ten model files plus the three shared ones
   (`control-common`, `implementation-common`, `mapping-common`) and the
   `shared-constraints/*.ent` entities. The imports matter: `label` and `sort-id`
   appear **zero** times in `catalog.xml`.
2. **NIST's own published SP 800-53 catalog**, already vendored at
   `lib/data/catalogs/`. What NIST itself emits is the strongest available
   evidence that a prop name is legitimate.
3. The model reference pages.

**The limit, stated because it changes how to read this document:** absence from
`allowed-values` does **not** prove a name is undefined. NIST documents and emits
props it never constrains — `label` and `sort-id` are exactly that. Every
"NOT DEFINED" below was therefore cross-checked against what NIST publishes, not
merely against the constraint set. Three of my own suspicions died at that step
and appear under *Cleared* rather than as findings.

Neither JSON Schema nor XSD carries any of this, which is the premise of #1106
and is confirmed: `EXAMINE`, `sort-id`, `control-origination` and `sp-corporate`
appear in **zero** of the eight baked-in XSDs.

## The rule everything below turns on

> "When a `ns` is not provided, its value should be assumed to be
> `http://csrc.nist.gov/ns/oscal` and the name should be a name defined by the
> associated OSCAL model."

So an unnamespaced prop is a claim that NIST defined it. Most findings here are
that claim being made falsely.

---

## Findings

### F1 — `implementation-status` is emitted as a prop; in 1.2.2 it is an assembly

**SSP, `oscal_ssp_export_service.rb:626` · CDEF, `oscal_component_definition_export_service.rb:354`**

```ruby
props << { "name" => IMPLEMENTATION_STATUS, "value" => nist }
```

In OSCAL v1.2.2 `implementation-status` is a `define-assembly` with a required
`state` flag, attached to exactly one place — `by-component`:

```xml
<define-assembly name="implementation-status">
  <define-flag name="state" as-type="token" required="yes">
```

It is **not** a prop anywhere, it does **not** attach to `implemented-requirement`
or `statement`, and it does not exist in the component-definition model at all
(**0 occurrences** in `component.xml`). This is the OSCAL 1.0 shape surviving in
a 1.2.2 export.

The correct form is already in the same file 79 lines earlier:

```ruby
entry[IMPLEMENTATION_STATUS] = { "state" => bc.implementation_status }   # :547
```

So the SSP exporter does it correctly for `by-component` and incorrectly for
`implemented-requirement`, and #1106's earlier vocabulary fix hardened the wrong
one of the two. **This supersedes that fix rather than extending it.**

### F2 — `control-origination` IS NIST-defined, and the issue says otherwise

**SSP, `oscal_ssp_export_service.rb:644`**

#1106 records this as a FedRAMP prop name borrowed under a SPARC namespace, and
proposes mapping to FedRAMP's vocabulary or renaming. **That premise is wrong for
v1.2.2.** NIST defines `control-origination` in the SSP model, with values:

```
organization · system-specific · customer-configured · customer-provided · inherited
```

SPARC emits the right name under `https://sparc.local/ns` with the wrong values
(`System Specific`, `Inherited` — title-case). The fix is therefore *simpler*
than the issue proposed: drop the `ns` and map to NIST's tokens. No FedRAMP
namespace, no rename.

### F3 — six CDEF props assert NIST definitions that do not exist

**`oscal_component_definition_export_service.rb:430-433, 354-356`**

`severity`, `rule-id`, `group-id`, `stig-id`, `control-origin`, `baseline-priority`
— all emitted with no `ns`, none defined by NIST in any model. These are DISA/STIG
vocabulary and SPARC's own, sitting in NIST's namespace.

The same file already does this correctly one line later, which is the pattern to
copy: `{ "name" => "cci", "ns" => "http://cyber.mil/cci", ... }`.

### F4 — the profile exporter lets an author name any prop in NIST's namespace

**`oscal_profile_export_service.rb:118-121`**

```ruby
next unless field.field_name.start_with?("prop:")
prop_name = field.field_name.delete_prefix("prop:")
props << { "name" => prop_name, "value" => field.field_value }
```

Unbounded, and the only finding here that is open-ended rather than a fixed list:
whatever an author types after `prop:` becomes a name asserted as NIST's. Needs a
namespace at minimum, and probably an allow-list.

### F6 — SAP and catalog props with no NIST definition

| Prop | Site | Status |
|---|---|---|
| `assessment-schedule`, `assessment-scope` | `oscal_assessment_plan_export_service.rb:216,224` | No `ns`, not NIST-defined |
| `impact-level`, `priority` | `oscal_catalog_export_service.rb:120,124` | No `ns`, not emitted by NIST's own catalog |

### F7 — `sparc.local` is not a usable namespace, and it is not applied consistently

`.local` is reserved for mDNS (RFC 6762): not resolvable, not ownable, and it
ships in every exported artifact as SPARC's identity. Beyond #1106's own framing,
the audit found the consistency problem is worse than the URI choice:

* `SPARC_NS` is defined **only** in the SSP exporter (`:41`).
* The SAP exporter hardcodes the literal string twice (`:85`, `:274`).
* It also appears in `lib/data_mappings/ssp_excel.json` (4 occurrences).
* CDEF uses a different shape entirely — `https://sparc.local/component-definitions/#{id}`.

**Owner decision required:** the replacement URI. A namespace is an identity
claim in every artifact SPARC exports, so this is not mine to pick. Once chosen,
it wants one shared constant, not five call sites.

---

## Cleared — checked and NOT findings

Recorded because each was a plausible defect that measurement killed, and because
re-raising them later would waste the same time twice.

| Suspicion | Why it is fine |
|---|---|
| Catalog `label` / `sort-id` emitted with no `ns` | **NIST's own 800-53 catalog does exactly this** — 12,831 `label` and 1,196 `sort-id` props, no `ns`. Correct as-is |
| SAP `method` emitted with no `ns` | NIST defines `method` on `activity` in the OSCAL namespace with values `EXAMINE`/`INTERVIEW`/`TEST`; SPARC's `.upcase` produces exactly those. It is even `min-occurs=1`, so emitting it is required. Correct as-is |
| `by-component` `implementation-status` carrying raw SPARC vocabulary | `SspByComponent::IMPLEMENTATION_STATUSES` already **is** NIST's vocabulary — `implemented partial planned alternative not-applicable`. No mapping needed |
| CDEF `cci` prop | Correctly namespaced to `http://cyber.mil/cci` |
| **SSP `validation-type` / `validation-reference`** (was F5 — **WITHDRAWN**) | **NIST-defined.** They arrive through `shared-constraints/allowed-values-component_component_property-name.ent`, one of **10** entity files `implementation-common.xml` includes. The hand audit read only the top-level metaschemas and could not see them. Correct as emitted |

Note in passing: NIST publishes `method`, `implementation-level`,
`contributes-to-assurance` and `aggregates` under a **second** NIST namespace,
`http://csrc.nist.gov/ns/rmf` — worth knowing before assuming "NIST" means one URI.

---

## Superseded by the generated dataset (slice 0)

This document was produced by hand. `lib/oscal_conformance/<version>/` is now
generated from the same authority by `bin/rails oscal:bundle_conformance`, and it
**resolves entity includes the hand pass missed** — `implementation-common.xml`
alone pulls in 10 `.ent` files. Two corrections came out of that:

* **F5 is withdrawn** (above). Automation found `validation-type` legitimate;
  acting on the hand audit would have namespaced two conforming NIST props.
* The machine verdict over every prop SPARC emits **with no `ns`** is
  **13 violations of 18**. The other five — catalog `label`/`sort-id`, SSP
  `validation-type`/`validation-reference`, SAP `method` — are conformant.

Where this document and the generated dataset disagree, **the dataset wins**.

## Coverage — what this pass did and did not do

| Done | Not yet done |
|---|---|
| Complete prop inventory, all 8 exporters | Enumerated-field sweep vs the 1.2.2 schema, noting `allOf` (enforced) vs `anyOf` (silently violable) |
| `ns` correctness for every prop | Required-field and cardinality sweep (e.g. `statements` `minItems: 1`) |
| Vocabulary check for every prop with a NIST-defined name | SAR and POA&M value vocabularies in depth |
| Namespace consistency across exporters and data mappings | Referential integrity — `role-id` resolution, which is #1116 |

The eighth model is **Mapping**, which #1106's original text omitted and its own
addendum corrects; it is included above and its only props are `type=catalog` on
mapping resources.

## Suggested sequencing

F1 and F2 are the two that produce *wrong documents a consumer will misread*, and
both are small. F3/F6 are one mechanical pattern applied in five places and
should follow the F7 namespace decision so the fix is applied once. F4 is the only
one needing a design call beyond the namespace.
