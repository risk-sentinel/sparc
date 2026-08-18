# Data Isolation & Compliance Structure

How SPARC organizes and isolates data across the compliance hierarchy —
from an enterprise down through individual authorization boundaries and the
OSCAL artifacts that document each system. This is the canonical reference
for anyone building **multi-system environments** in SPARC.

*Current as of app version v1.13.0.*

## The hierarchy

SPARC models the real-world NIST RMF / FedRAMP / DoD compliance structure:

- **Organization** — a large entity (agency, company, DoD mission area) that
  oversees multiple systems, analogous to DoD's **System of Systems (SoS)**
  concept where many independent systems work toward a shared mission.
- **Authorization Boundary** — a separately managed scope with its own ATO (or
  cATO in DoD). Each boundary is the primary **isolation unit**: authenticated
  users see and act only on documents in the boundaries they have access to
  (`BoundaryScopedDocument`, NIST AC-3, v1.11.1). Boundaries can inherit
  controls from shared Profiles, Catalogs, or Components.
- **Profiles** — a tailored selection and parameterization of controls from a
  Catalog (e.g. a FedRAMP Moderate baseline).
- **CDEFs (Component Definitions)** — reusable/inherited components that
  implement controls, mapped into SSPs.
- **SSP (System Security Plan)** — documents how controls are implemented within
  a specific Authorization Boundary; imports a Profile and references Components.
- **SAP (Security Assessment Plan)** — defines how the SSP will be assessed;
  imports the SSP.
- **SAR (Security Assessment Report)** — records assessment findings; imports
  the SAP.
- **POA&Ms (Plans of Action & Milestones)** — track remediation of unresolved
  findings from the SAR.

Relationships between the OSCAL layers are maintained via OSCAL `import-*`
statements for end-to-end traceability.

## Isolation model

- **Boundary-scoped access** — the authorization boundary is the access-control
  perimeter. Users only see/act on documents in boundaries they belong to. The
  web UI enforces the same rules as the API (v1.11.1, NIST AC-3). See
  [RBAC](RBAC) for how roles are scoped to instances vs. boundaries.
- **A system security plan, assessment plan, assessment result or POA&M must
  belong to a boundary.** These four are per-system by definition, so from
  v1.16.0 the boundary is required when the document is created. Documents
  created before that rule and left unattached are **not** open to everyone —
  they are visible to Instance Admins only until someone attaches them (see
  [Authorization Boundaries](User-Guide-Authorization-Boundaries)). Earlier
  releases treated a boundary-less document of these types as instance-wide and
  showed it to every signed-in user.
- **Publishing the control library never publishes system data.** With
  `SPARC_PUBLIC_CATALOGS=true` an anonymous visitor can read the Controls layer —
  catalogs, baselines, mappings, component definitions, converters, and the OSCAL
  downloads for each — and nothing else. Writing stays signed-in, the API still
  requires a token, and every boundary document remains private. With the setting
  off (the default) the whole Controls layer requires a sign-in too.
- **Evidence is deliberately exempt.** Evidence can be leveraged and inherited
  across boundaries, so an evidence record with no boundary is a legitimate
  instance-wide artifact and remains visible accordingly. Component definitions
  are likewise instance-wide: a CDEF states that a control *can* be satisfied,
  not how one particular system implements it.
- **Organization grouping** — organizations group boundaries for multi-org
  (System-of-Systems) instances, each with UUID-based audit traceability.

## Structure map

```mermaid
mindmap
  root((SPARC Compliance Structure))
    Organization 1
      "System of Systems / Enterprise / Agency"
      Authorization Boundary A
        Profile (Tailored Baseline)
          "FedRAMP Moderate / NIST 800-53 / DoD IL4"
        Component Definitions (CDEFs)
          "Reusable / Inherited / Supplier Components"
        SSP (System Security Plan)
          "Implementation within Boundary A"
          "Imports Profile"
          "References Components"
        SAP (Assessment Plan)
          "Imports SSP"
        SAR (Assessment Results)
          "Imports SAP"
        POA&Ms
          "Derived from SAR"
      Authorization Boundary B
        Profile (Same or different)
        Component Definitions
        SSP
        SAP
        SAR
        POA&Ms
    Organization 2
      "Another Line of Business / Region / Division"
      Authorization Boundary C
        Profile
        CDEFs
        SSP
        SAP
        SAR
        POA&Ms
      Authorization Boundary D
        Profile
        CDEFs
        SSP
        SAP
        SAR
        POA&Ms
```

## Related

- [RBAC](RBAC) — role scoping (instance vs. authorization boundary) and permissions
- [Core Functions](Core-Functions) — Authorization Boundary Management, the OSCAL layers, and document workflows
- [Architecture](Architecture) — the domain model and how these entities relate in the schema
