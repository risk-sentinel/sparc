<!-- markdownlint-disable MD013 -->
# SPARC Architecture & Data Model

A single-page architectural overview of SPARC: the request/processing flow and
the domain entity-relationship model. For the narrative service-layer breakdown
see the wiki [Architecture](https://github.com/risk-sentinel/sparc/wiki/Architecture)
page; for OSCAL field-level mapping see [`oscal-data-mapping.md`](oscal-data-mapping.md)
and [`data_mapping/`](data_mapping/).

> Created for #606 to close the "no top-level architecture diagram / no
> consolidated ERD" gaps noted in [`MAP.md`](MAP.md).

---

## 1. Component & data flow

SPARC is a Rails 8.1 monolith: controllers are thin, business logic lives in
`app/services/`, and long-running work runs on Solid Queue. OSCAL is validated
against NIST schemas baked into the container.

```mermaid
flowchart TB
    subgraph Clients
        UI[Web UI — Hotwire/Turbo]
        API[API clients / service accounts]
    end

    subgraph Rails["Rails 8.1 application"]
        CTRL[Controllers<br/>web + Api::V1]
        SVC[Service layer<br/>parsers · exporters · validators<br/>mutation · federation · converters]
        MODELS[(ActiveRecord models)]
        VAL[OSCAL schema validation<br/>NIST v1.1.2 — baked in]
    end

    subgraph Async["Solid Queue (background)"]
        DCJ[DocumentConversionJob]
        AWS[AwsLabsCdefRefreshJob]
        DDM[Deferred data migrations]
    end

    DB[(PostgreSQL 15<br/>JSONB-heavy)]
    STORE[(Active Storage<br/>local / S3)]

    subgraph External
        AWSLABS[AWS Labs OSCAL CDEFs]
        PEERS[Federation peers<br/>HMAC-signed bundles]
        HDF[HDF / MITRE SAF]
    end

    UI --> CTRL
    API --> CTRL
    CTRL --> SVC
    SVC --> MODELS
    SVC --> VAL
    MODELS --> DB
    CTRL --> STORE
    CTRL -. enqueue .-> Async
    DCJ --> SVC
    AWS --> AWSLABS
    SVC <--> PEERS
    SVC <--> HDF
```

**Document import pipeline:** upload → `DocumentConversionJob` → format detected →
dispatched to the per-type/per-format parser → document + controls + fields
persisted → `ConversionJob` status updated (`pending → processing → completed/failed`).

**OSCAL export:** model → `Oscal*ExportService` → schema-validated → JSON/XML
download. CDEF mutations validate **pre-commit** via `CdefMutationService` (v1.8.0).

---

## 2. Domain ERD

The **Authorization Boundary** is the organizing container for a system's
compliance artifacts. Each document type follows a consistent
Document → Control → ControlField hierarchy (POA&M is the exception).

For readability the model is shown in two views: the **documents** an
authorization boundary contains, and the boundary's **context** (organization,
access control, catalog, and evidence). `AUTHORIZATION_BOUNDARY` is the bridge
that appears in both.

#### 2a. Documents within an authorization boundary

Each document type follows a `Document → Control → ControlField` hierarchy;
POA&M is the exception, decomposing into items/risks/observations/findings.

```mermaid
erDiagram
    AUTHORIZATION_BOUNDARY ||--o| SSP_DOCUMENT : has
    AUTHORIZATION_BOUNDARY ||--o| SAP_DOCUMENT : has
    AUTHORIZATION_BOUNDARY ||--o| SAR_DOCUMENT : has
    AUTHORIZATION_BOUNDARY ||--o{ POAM_DOCUMENT : has
    AUTHORIZATION_BOUNDARY ||--o{ CDEF_DOCUMENT : "has (via sub-boundaries)"
    AUTHORIZATION_BOUNDARY }o--o| PROFILE_DOCUMENT : "baseline"

    PROFILE_DOCUMENT ||--o{ PROFILE_CONTROL : has
    PROFILE_CONTROL ||--o{ PROFILE_CONTROL_FIELD : has

    SSP_DOCUMENT ||--o{ SSP_CONTROL : has
    SSP_CONTROL ||--o{ SSP_CONTROL_FIELD : has
    SSP_DOCUMENT }o--o| PROFILE_DOCUMENT : "resolves"

    SAR_DOCUMENT ||--o{ SAR_CONTROL : has
    SAR_CONTROL ||--o{ SAR_CONTROL_FIELD : has

    SAP_DOCUMENT ||--o{ SAP_CONTROL : has
    SAP_CONTROL ||--o{ SAP_CONTROL_FIELD : has

    CDEF_DOCUMENT ||--o{ CDEF_CONTROL : has
    CDEF_CONTROL ||--o{ CDEF_CONTROL_FIELD : has

    POAM_DOCUMENT ||--o{ POAM_ITEM : has
    POAM_DOCUMENT ||--o{ POAM_RISK : has
    POAM_DOCUMENT ||--o{ POAM_OBSERVATION : has
    POAM_DOCUMENT ||--o{ POAM_FINDING : has
    POAM_DOCUMENT }o--o| SSP_DOCUMENT : "remediation source"
```

#### 2b. Boundary context — organization, RBAC, catalog & evidence

```mermaid
erDiagram
    ORGANIZATION ||--o{ AUTHORIZATION_BOUNDARY : owns
    AUTHORIZATION_BOUNDARY ||--o{ USER_ROLE : scopes
    USER ||--o{ USER_ROLE : has
    ROLE ||--o{ USER_ROLE : grants

    CONTROL_CATALOG ||--o{ CONTROL_FAMILY : has
    CONTROL_FAMILY ||--o{ CATALOG_CONTROL : has

    AUTHORIZATION_BOUNDARY ||--o{ EVIDENCE : has
    EVIDENCE ||--o{ ATTESTATION : "signed off by"
    AUTHORIZATION_BOUNDARY ||--o{ KSI_VALIDATION : tracks
    AUTHORIZATION_BOUNDARY ||--o{ LEVERAGED_AUTHORIZATION : "leverages / leveraged-by"
```

### Key points

- **Catalog → Profile → SSP:** a `ControlCatalog` (e.g. NIST 800-53 Rev 5) is
  tailored by a `ProfileDocument` (from a baseline), which resolves into the
  controls an `SspDocument` implements.
- **Three-level hierarchy:** SSP / SAR / SAP / CDEF / Profile each follow
  `*Document → *Control → *ControlField`. **POA&M** instead decomposes into
  `PoamItem`, `PoamRisk`, `PoamObservation`, and `PoamFinding`.
- **RBAC:** `User`—`UserRole`—`Role`, where `UserRole` is optionally scoped to an
  `AuthorizationBoundary` (instance-scoped when unscoped). See the wiki
  [RBAC](https://github.com/risk-sentinel/sparc/wiki/RBAC) page.
- **Back-matter** resources (citations, evidence, rlinks) are first-class
  `BackMatterResource` rows across document types (v1.8.0), and can be shared
  through the authoritative-source federation system (#372).
