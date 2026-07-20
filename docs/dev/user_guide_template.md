<!--
  Internal authoring template for SPARC wiki User Guides (issue #771).

  This file lives under docs/dev/ ON PURPOSE — it must NOT be copied into the
  published wiki. wiki/PUSH_TO_WIKI.sh only publishes wiki/*.md, so keeping the
  template here guarantees it never becomes a live wiki page.

  Every wiki/User-Guide-*.md page follows the structure below so the guides read
  as one consistent set (acceptance criterion: "Guides follow consistent
  formatting and style"). Copy the skeleton, delete the guidance comments, and
  fill each section. Delete any section that genuinely does not apply rather than
  leaving it empty.

  House style (from existing wiki pages + .markdownlint.json):
    - One H1 (`#`) = the page title, matching the file name with spaces.
    - `##` major sections, `###` subsections, `####` individual items.
    - Intra-wiki links use bare page names: [Screens & UI](Screens).
    - Repo links use full GitHub URLs.
    - Fenced code blocks carry a language hint (```bash, ```json, ```text).
    - `---` between major sections.
    - Wrap prose at ~80 columns (MD013 = 80; tables and code blocks are exempt).
    - Mermaid diagrams render natively in the GitHub wiki — use ```mermaid.
-->

# User Guide: <Screen or Workflow Area Name>

One or two sentences: what this area of SPARC does and which real-world
compliance task it supports. Keep it outcome-focused ("Use System Security
Plans to document how your system meets each NIST 800-53 control"), not a
feature list.

**Who this is for:** the role(s) that use this area day to day (e.g. ISSO,
assessor, org admin). Link the [RBAC](RBAC) page for the permission detail.

---

## Before you start

- **Access:** the role or permission required to see and use these screens
  (link [RBAC](RBAC)).
- **Prerequisites:** artifacts or setup that must already exist (e.g. "an SSP
  requires a published baseline, and optionally a Component Definition").
- **Where to find it:** the navigation path, e.g.
  *Implementation → System Security Plans*, or the sidebar location.

---

## At a glance

A `mermaid` diagram of the workflow or lifecycle when it clarifies the flow.
Use `flowchart LR` for step sequences and `stateDiagram-v2` for status
lifecycles. Omit this section if a diagram would not add anything.

```mermaid
flowchart LR
    A[Start] --> B[Do the thing] --> C[Result]
```

---

## Primary use cases

The main jobs users come to this area to accomplish — a short bulleted list.
**Mandatory for the OSCAL document guides (SSP, SAP, SAR, POA&M)**, and each
must name the OSCAL document(s) involved.

- Use case one — one line.
- Use case two — one line.

---

## How to …

One `###` subsection per task, each a numbered, click-by-click walkthrough that
uses the **real button labels and field names** (source them from
[Screens & UI](Screens) and, for OSCAL field meaning, from the repo's
`docs/data_mapping/`). Prefer several small tasks over one giant procedure.

### How to <do the primary task>

1. Go to *Nav → Screen*.
2. Click **<real button label>**.
3. Fill in **<field>** — what it means and how to choose a value.
4. …
5. The result: what the user should now see.

### How to <do the next task>

1. …

---

## Tips & best practices

- Practical guidance, conventions, and gotchas that make the workflow smoother.

---

## Troubleshooting

Common failure states and what to do — e.g. a document stuck on the processing
spinner, a validation error on OSCAL export, a permission-denied banner.

| Symptom | Likely cause | What to do |
|---|---|---|
| … | … | … |

---

## Related guides

Cross-links to adjacent guides (acceptance criterion: "Cross-links between
related guides") and to the reference inventory:

- [User Guides index](User-Guides)
- [<Adjacent guide>](User-Guide-<Name>)
- [Screens & UI](Screens) — exhaustive element-level reference for these screens.
