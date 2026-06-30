# Accessibility Color Refactor — WORM Plan (v1.8.6+)

**Status:** Discovery + proposal. No code changed yet.
**Author:** drafted for review on branch `bug/v1.8.6_ui_burndown`.
**Related:** #572 (UI test net umbrella), #599 (Layer 3 axe sweep), #602 (login
a11y burndown), #603 (Section 508 mapping), #604 (merged sweep).

---

## 1. Why this document exists

The #599 accessibility sweep captured a full baseline against the deployed app:
**1,485 `color-contrast` violation nodes across 42 pages** (plus ~23 structural
issues). The first reflex — recoloring — would mean editing **36 ERB files**
containing **213 inline `style="…#hex…"`** occurrences. That is the wrong fix:
it spreads color + opacity + contrast decisions across the markup, so every
future palette or a11y change re-touches dozens of files. The opposite of
**WORM (Write Once, Read Many)**.

This plan defines how to move color/contrast ownership **into CSS as the single
source of truth**, fix WCAG 2.1 AA once, and let the #599 axe ratchet keep it
fixed — so contrast becomes a solved, self-maintaining property of the design
system rather than a recurring chore.

---

## 2. Discovery — how colors are produced today

### 2.1 The contrast debt collapses to a few patterns

From the `tests/ui-smoke/_contrast_probe.py` run (vs prod, 2026-05-31): 1,485
nodes → **37 distinct color-pairs**, of which **6 pairs cause ~93%**:

| Nodes | Pages | Pair | Source pattern |
|------:|------:|------|----------------|
| 425 | 7 | `#0d6efd` on `#f5f5f5` | `.btn-outline-primary` (Bootstrap default blue) |
| 356 | 8 | `#d63384` on `#f5f5f5` | `<code>` (Bootstrap default pink) |
| 257 | 2 | `#fff` on `#2980b9` | inline `style="background:#2980b9;color:white"` action button |
| 253 | 1 | `#95a5a6` on `#95a5a622` | **tinted-badge pattern** (text on 13%-alpha fill) |
| 51 | 1 | `#fff` on `#f39c12` | inline amber action button |
| 33 | 5 | `#6c757d` on `#f5f5f5` | `.btn-outline-secondary` (Bootstrap default grey) |

The long tail (~110 nodes) is more of the **same two shapes**: the tinted-badge
pattern in different hues, and inline-styled section headings
(`<h3 style="color:#3498db">`) / status pills.

### 2.2 Three distinct sources, three distinct fixes

1. **Bootstrap component defaults we never overrode** — `<code>`, and the
   `.btn-outline-*` small variants. Bootstrap bakes literal default hex into
   `--bs-btn-color`, so our `--bs-*-rgb` token overrides never reached them.
   → Pure CSS override (planned Round 1, **not yet committed** — the branch
   currently holds only the captured baseline + the SAP CSP fix): override
   `<code>` and `.btn-outline-primary/secondary/success/danger` to re-point at
   `--sparc-*` tokens. Verified arithmetically: light ≥4.5:1, dark ≥4.7:1.

2. **Helper-driven tinted status badges** — the structural problem. Helpers
   return a raw hex; views render:
   ```erb
   style="background: <%= color %>22; color: <%= color %>; border: 1px solid <%= color %>44;"
   ```
   `color:#X` on `background:#X22` (13% alpha of the same hue) is **~2:1 by
   construction** — un-fixable by darkening the hex. Needs a component.

   Color-emitting helpers (the semantic source):
   - `app/helpers/application_helper.rb`: `ssp_status_color`, `sar_status_color`,
     `cdef_severity_color`, `sap_method_color`, `sap_objective_status_color`
     (aliased `sar_objective_status_color`), `profile_priority_color`,
     `ab_status_color` — all return **raw hex** (e.g. `#e74c3c`).
   - `app/helpers/converters_helper.rb`: `converter_status_color`,
     `converter_relationship_color` return **semantic keys already**
     (`"success"`, `"warning"`, …); `converter_type_color` returns raw hex.
   - `app/helpers/control_mappings_helper.rb`: `mapping_status_color`.

3. **Hardcoded inline `style=` hex** in views — action buttons
   (`background:#2980b9`, `#f39c12`), step headings (`color:#3498db` etc.),
   dashboard/login "layer" labels. Color literally typed into markup.

### 2.3 A WORM foundation already exists (partially)

`app/assets/stylesheets/sparc-theme.css` already defines **AA-passing**
semantic badge classes (Bootstrap alert palette), with light + dark variants:

| Class | Light fg/bg | Ratio |
|-------|-------------|------:|
| `.badge-ok`   | `#155724` on `#d4edda` | 7.21 |
| `.badge-warn` | `#856404` on `#fff3cd` | 7.21 |
| `.badge-fail` | `#721c24` on `#f8d7da` | 7.08 |
| `.badge-info` | `#1a5276` on `#d6eaf8` | 7.65 |

(Actual values from `sparc-theme.css:587`; all comfortably pass AA. Dark-theme
variants already defined alongside.)

**Some views already use these** (e.g. `cdef_documents/index` status column)
— while **other views use the inline tinted pattern** for the same concept.
The refactor is therefore largely *consolidation onto a pattern that already
exists and already passes*, not green-field invention.

### 2.4 Scope inventory

- **36** ERB files with inline color/background hex; **213** occurrences.
- **~9** helper methods are the semantic origin of most badge colors.
- **Existing** `.badge-*` (4 variants) + `.sparc-source-badge`,
  `.sparc-oscal-enriched` (these last two are themselves AA failures today).

---

## 3. Proposed WORM architecture

**Principle:** markup declares *meaning* (a semantic class); CSS owns *color +
contrast + opacity*; helpers map domain values → semantic variant keys (never
hex). Changing the palette or fixing AA = **one CSS file, zero view edits**.

### 3.1 CSS: one status-pill component, complete variant set

Extend the existing badge system into a complete, AA-correct set (single source
of truth, light + dark in one place):

```css
/* Status pill — semantic variants; every pair verified WCAG 2.1 AA >=4.5:1 */
.sparc-status { display:inline-block; padding:.2rem .6rem; border-radius:.25rem;
                font-weight:600; font-size:.78rem; border:1px solid; white-space:nowrap; }
.sparc-status--success { color:#0f5132; background:#d1e7dd; border-color:#badbcc; }
.sparc-status--warning { color:#664d03; background:#fff3cd; border-color:#ffecb5; }
.sparc-status--danger  { color:#842029; background:#f8d7da; border-color:#f5c2c7; }
.sparc-status--info    { color:#055160; background:#cff4fc; border-color:#b6effb; }
.sparc-status--neutral { color:#41464b; background:#e2e3e5; border-color:#d3d6d8; }
.sparc-status--purple  { color:#5b2c6f; background:#ebdef0; border-color:#d7bde2; }
[data-bs-theme="dark"] .sparc-status--success { … }   /* dark overrides, once */
```

(Variants map the full domain space: high/medium/low severity, P1/P2/P3,
passing/failing/pending/in-progress, active/authorized/draft/deauthorized,
examine/interview/test, OSCAL/import sources, converter types.)

### 3.2 Helpers: return semantic variant keys, not hex

Normalize every color helper to return a `sparc-status--*` variant key:

```ruby
# before:  cdef_severity_color("high") => "#e74c3c"
# after:   cdef_severity_variant("high") => "danger"
SEVERITY_VARIANT = { "high"=>"danger", "medium"=>"warning", "low"=>"info", "info"=>"neutral" }.freeze
def cdef_severity_variant(sev) = SEVERITY_VARIANT[sev.to_s.downcase] || "neutral"
```

Keep the old `*_color` methods temporarily as deprecated shims (or delete once
all callers migrate) to keep the diff reviewable.

### 3.3 Views: declare meaning, delete inline style

```erb
<%# before %>
<span class="rounded fw-semibold" style="background: <%= c %>22; color: <%= c %>; border:1px solid <%= c %>44;">…</span>
<%# after %>
<span class="sparc-status sparc-status--<%= cdef_severity_variant(doc.severity) %>">…</span>
```

Inline action buttons (`style="background:#2980b9;color:white"`) → existing
`.btn-primary` / `.btn-warning` (the latter already enforces black-on-amber AA).
Step headings (`<h3 style="color:#3498db">`) → semantic heading classes
(`.sparc-step-heading--controls` etc.) defined once in CSS.

### 3.4 Outcome

After migration, **no `app/views/**` file contains a color hex.** A lint guard
(grep in CI, optional) can keep it that way. Future contrast work = edit
`sparc-theme.css` only; the axe ratchet proves it stays AA forever.

---

## 4. Execution plan (iterative, one commit per round)

Each round: fix → re-measure locally (see §5) → commit (hash-trackable) →
shrink `tests/ui-smoke/a11y_baseline.json` by the cleared entries.

| Round | Work | Files | ~Nodes cleared | WORM? |
|------:|------|-------|---------------:|-------|
| **1** | Bootstrap defaults: `<code>`, `.btn-outline-*` | 1 CSS | ~850 | yes |
| **2** | `.sparc-status` component + helper variant keys; migrate tinted-badge views | 1 CSS, ~9 helpers, ~12 views | ~470 | yes |
| **3** | Inline action buttons → `.btn-*`; step/layer headings → semantic classes | 1 CSS, ~10 views | ~110 | yes |
| **4** | Structural: `select-name` ×15 (label/aria-label), `label` ×1, `scrollable-region-focusable` ×1 (`#consentBannerBody` tabindex, #602), `meta-refresh` ×6 | views/controllers | ~23 (non-color) | n/a |
| **Final** | `VERSION` 1.8.5→1.8.6; flip SC Section-508 row toward Implemented as count drops; re-capture baseline; PR | config, docs, baseline | — | — |

Note: Round 4 `meta-refresh` needs investigation — likely an auto-refresh
`<meta>` on a status/processing page; replace with a proper redirect or
Turbo-stream poll (it's a WCAG 2.2.1/2.2.4 timing failure, not color).

---

## 5. Validation (local docker, real measurement)

Per decision: measure each round **before merge** against a local instance
(prod can't reflect the changes until deployed).

```bash
# 1. Bring up the branch (base compose mounts .:/rails — live source):
docker compose up --build -d            # web on :3000, seeds data
# 2. Mint a local admin SA token (or enable local login) for authed pages.
# 3. Re-measure the contrast clusters + run the a11y sweep against localhost:
cd tests/ui-smoke
SPARC_SMOKE_BASE_URL=http://localhost:3000 SPARC_SMOKE_SA_TOKEN=<local> \
  uv run python _contrast_probe.py                     # cluster counts drop per round
SPARC_SMOKE_BASE_URL=http://localhost:3000 SPARC_SMOKE_SA_TOKEN=<local> \
  uv run pytest test_accessibility.py --browser chromium --browser firefox
```

Every variant's contrast is also verified arithmetically (WCAG relative-
luminance formula) before committing, so the math and the browser agree.
Run `bundle exec rubocop` on changed helpers; run the full nav sweep to confirm
no navigation regressions.

**Caveat to record in the PR:** node-count reductions cited will be *local*
numbers; the authoritative prod re-capture happens post-deploy and the committed
baseline is updated then.

---

## 6. Risks & decisions

- **Visual change.** Consolidating onto `.badge-*`-style fills changes some
  status chips from "thin tinted" to "soft solid." This is a deliberate, minor
  visual shift toward the existing (already-used) badge look — flag for design
  sign-off in the PR with before/after screenshots from the local instance.
- **Dark theme.** Every variant needs a verified dark pair; the existing
  `.badge-*` dark overrides are the template.
- **Helper churn vs. shims.** Returning variant keys changes helper contracts;
  keep deprecated `*_color` shims for one release if any non-view caller exists
  (check specs/JSON serializers before deleting).
- **Scope of v1.8.6.** Rounds 1–4 are all WORM/structural and shippable
  together. If the badge migration (Round 2) proves large in review, it can be
  its own PR/patch; Rounds 1, 3, 4 still stand alone.
- **Not in scope:** semantic restructure of heatmaps or any non-contrast visual
  redesign; this plan is strictly contrast + the WORM mechanism.

---

## 7. Definition of done

- No color hex literals in `app/views/**` (verifiable by grep).
- All color/contrast owned by `sparc-theme.css`; helpers return semantic keys.
- Local axe sweep shows the targeted clusters cleared; remaining items stay
  baselined (ratchet active — no new debt can land).
- `VERSION` bumped to 1.8.6; baseline re-captured post-deploy; Section 508
  mapping status advanced to reflect the reduction.
