<!-- markdownlint-disable MD013 -->
# OSCAL 1.2.2 support, and what validating across versions revealed

Closes [#1020](https://github.com/risk-sentinel/sparc/issues/1020). Written down
because two of the three findings here are about **NIST's schemas**, not about
SPARC, and the next person to see a 1.2.0 validation failure should not spend a
day on it.

## What changed

- `OscalSchema::SUPPORTED_VERSIONS` gains **1.2.2**, NIST's current release.
  `MAPPING_VERSIONS` gains it too — `mapping` exists only from 1.2.0, and the two
  lists drifting apart would silently skip that schema in the seed task. A spec
  now asserts every 1.2.x release appears in both.
- All eight document-type schemas for 1.2.2 fetch cleanly from NIST's release
  assets by the URL template the seed task already uses (55KB–152KB each).
- **`DEFAULT_VERSION` stays `1.1.2`.** Adding a version SPARC can validate
  *against* is a different decision from changing the version it *emits*.

## Finding 1: SPARC's exports are valid on 1.2.2

The question behind #1020 was whether 1.2.x's tighter constraints break our own
output — 1.2.x applies the non-empty-string datatype to `title` fields that 1.1.x
left unconstrained, which is exactly the kind of change that turns a passing
exporter into a failing one.

Every exporter, against every version, using live documents:

| Export | 1.1.2 | 1.2.0 | 1.2.1 | 1.2.2 |
|---|---|---|---|---|
| SSP | ✅ | ✅ | ✅ | ✅ |
| Component definition | ✅ | ✅ | ✅ | ✅ |
| Profile | ✅ | ✅ | ✅ | ✅ |
| Catalog | ✅ | ✅ | ✅ | ✅ |
| POA&M | ✅ | ❌ 12 | ✅ | ✅ |
| SAR | ✅ | ❌ 12 | ✅ | ✅ |

**Nothing breaks on 1.2.2.** The only failures are on 1.2.0, and they are not
ours — see below.

## Finding 2: OSCAL **1.2.0** rejects documents that 1.1.x, 1.2.1 and 1.2.2 accept

Both failing exports fail for one reason, twelve times each:

```
/plan-of-action-and-milestones/poam-items/0/related-risks/0/risk-uuid:
  object property ... is a disallowed additional property
/assessment-results/results/0/findings/28/related-risks/0/risk-uuid:
  object property ... is a disallowed additional property
```

The cause is in the schema. Searching each release for a definition carrying a
`risk-uuid` property:

| Version | definitions with `risk-uuid` |
|---|---|
| **1.2.0** | **0** |
| 1.2.1 | 1 — `oscal-poam-oscal-assessment-common:associated-risk`, `properties: [remarks, risk-uuid]`, `required: [risk-uuid]`, `additionalProperties: false` |
| 1.2.2 | identical to 1.2.1 |

**1.2.0 omits the `associated-risk` definition entirely.** `risk-uuid` has nothing
to match, and `additionalProperties: false` turns that into a violation — for a
property the same release *requires* elsewhere in the model. 1.2.1 restores it.

This is confirmed against **two unrelated producers**: SPARC's own POA&M and SAR
exporters, and hdf-cli's `hdf-amendments → oscal-poam` converter
([mitre/hdf-libs#236](https://github.com/mitre/hdf-libs/issues/236)). Both emit
`risk-uuid`; only 1.2.0 objects. Two independent implementations agreeing against
one schema release is what makes this a schema defect rather than a producer bug.

Recorded in code as `OscalSchema::KNOWN_DEFECTIVE_VERSIONS`, with a spec asserting
the entry names a version we actually support — so a 1.2.0 failure is explained at
the point someone meets it.

**Practical guidance: do not validate against 1.2.0.** It is kept in
`SUPPORTED_VERSIONS` because a consumer may be pinned to it and we should be able
to reproduce what they see, not because it is a sensible target.

NIST fixed this in 1.2.1, so there is nothing to report upstream.

## Finding 3: 1.2.x tightening is real, just not for us

Validating hdf-cli's POA&M output across versions showed the same document going
from 3 violations on the 1.1.x line to 7 on 1.2.x, because 1.2.x applies the
non-empty-string datatype to `metadata.title`, `risks[].title` and
`poam-items[].title`. SPARC's exporters are unaffected — they do not emit empty
strings for those fields — but the mechanism is worth knowing, because an exporter
that starts emitting `""` for an absent optional value will pass 1.1.2 and fail
1.2.x.

## Reproducing

```ruby
# rails runner
%w[1.1.2 1.2.0 1.2.1 1.2.2].each do |v|
  doc = JSON.parse(OscalPoamExportService.new(PoamDocument.first).export)
  r = OscalSchemaValidationService.validate(:poam, doc, version: v)
  puts "#{v}: valid=#{r.valid?} errors=#{r.errors.size}"
end
```

Note `export` returns a JSON **string**, not a Hash — validating it unparsed
reports `Missing required root key ... Found: String`, which looks like an export
defect and is not one.
