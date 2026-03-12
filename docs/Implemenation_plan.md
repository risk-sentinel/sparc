# SPARC Open GitHub Issues – Implementation Strategy

Structured, prioritized roadmap for the 23 open issues in the SPARC GitHub report.

## Guiding Principles

- **Prioritization** — High-priority bugs and foundational items first  
- **Phased delivery** — Stability → core OSCAL → advanced features → deployment
polish
- **Dependencies respected** — Prerequisites completed before dependent work  
- **Testing-first mindset** — Regression suite (#100) early  
- **Compliance focus** — NIST OSCAL schema validation on all related changes  
- **Team size** — 3–5 developers (adjustable)  
- **Sprint length** — 2–4 weeks  
- **Total estimated duration** — 16–24 weeks (~4–6 months) with overlap

## Grouped Issues by Theme

### 1. Bugs & Quick Wins (High priority – Fix first)

- #142 – Large Excel uploads block UI (background + progress UX)  
- #178 – Safe delete confirmation with dependency checks  

### 2. Testing & Developer Experience (Foundation)

- #100 – Comprehensive automated regression testing suite  
- #134 – Enable HTTPS in development environment (mkcert + Rails config)  

### 3. OSCAL Core (Import/Export, Publication, Status)

- #163 – Unified catalog import/export (JSON/YAML/XML interoperability)  
- #177 – Extend Catalog import & management (locking, SHA digest, baseline impacts)
- #148 – OSCAL-compliant publication process for key document types  
- #149 – Status tracking for Baselines/Profiles, Components, Documents  
- #176 – Unified publication process for Profiles and Component Definitions  

### 4. OSCAL Entity Creation & Workflows

- #175 – Build Published Profile creation from baseline  
- #172 – Component Definition (CDEF) creation & import (incl. from Profile)  
- #173 – System Security Plan (SSP) creation & import (incl. from Profile)  
- #174 – Security Assessment Report (SAR) creation & import (incl. from Profile/SSP)
- #125 – End-to-end wizard for complete ATO Authorization Package  

### 5. Advanced OSCAL & Compliance Extensions

- #107 – Expand to support FedRAMP 20x framework  
- #108 – Expand sample data for FedRAMP 20x + traditional NIST 800-53  
- #133 – Documentation & guidance for building OSCAL data mapping files  

### 6. UI/UX & Navigation Improvements

- #167 – Enterprise/Organization visibility & navigation for admins  
- #171 – Interactive OSCAL document relationship diagram (Mermaid)  

### 7. API & Backend Enhancements

- #95 – Full CRUD API endpoints for Users and Projects (server mode only)  

### 8. Deployment Patterns (IaC)

- #109 – ECS Fargate deployment pattern (Terraform)  
- #110 – Standalone EC2 deployment pattern (Terraform)  
- #111 – Azure VM deployment pattern (Terraform)  

## Phased Roadmap

### Phase 1: Stabilization & Foundations (2–4 weeks)

**Goal:** Prevent data loss, improve dev experience, establish testing safety net

- Fix #142 (background jobs + Turbo Streams/polling)  
- Fix #178 (dependency-aware delete modal)  
- Implement #100 (RSpec/Capybara + RuboCop/Brakeman in CI)  
- Implement #134 (HTTPS localhost via mkcert)  

**Deliverables:** Stable dev env, >70–80% regression coverage, safe deletes

### Phase 2: OSCAL Import/Export & Publication Core (4–6 weeks)

**Goal:** Solid, interoperable, publishable OSCAL foundation

- #163 – YAML + full XML enhancement support, round-trip tests  
- #177 – Catalog locking, universal SHA digest, baseline impact multi-select  
- #149 – Status enum + lifecycle rules  
- #148 – Standardized publication metadata + validation  
- #176 – Unified publish/copy logic for Profiles & CDEFs  

**Deliverables:** All-format import/export, immutable published artifacts

### Phase 3: OSCAL Entity Creation & ATO Wizard (4–6 weeks)

**Goal:** Full artifact lifecycle + guided ATO package generation

- #175 – Profile creation from baseline + parameter validation  
- #172 – CDEF creation/import from Profile  
- #173 – SSP creation/import from Profile  
- #174 – SAR creation/import from Profile or SSP  
- #125 – Multi-step ATO wizard (all OSCAL layers)  

**Deliverables:** End-to-end traceable ATO package ZIP export

### Phase 4: Advanced Compliance & UX Polish (3–4 weeks)

**Goal:** FedRAMP readiness + better onboarding/navigation

- #107 – FedRAMP 20x extensions (KSIs, automation)  
- #108 – Dual sample sets + seed script flags  
- #133 – OSCAL data mapping documentation & guidance  
- #167 – Rename Environments → Enterprise + Organizations card  
- #171 – Mermaid OSCAL relationship diagram  

**Deliverables:** FedRAMP 20x support, improved admin UX & visuals

### Phase 5: API & Multi-Cloud Deployment (3–4 weeks – parallel with Phase 4)

**Goal:** Programmatic access + production IaC blueprints

- #95 – Versioned REST API for Users/Projects with RBAC  
- #109 – Terraform ECS Fargate pattern  
- #110 – Terraform EC2 standalone pattern  
- #111 – Terraform Azure VM pattern  

**Deliverables:** OpenAPI docs + deployable AWS/Azure blueprints

## Summary Timeline

| Phase | Duration     | Key Focus                          | Parallelizable? |
|-------|--------------|------------------------------------|-----------------|
| 1     | 2–4 weeks    | Bugs + Testing + Dev Env           | No              |
| 2     | 4–6 weeks    | OSCAL Core                         | Limited         |
| 3     | 4–6 weeks    | Entity Creation + Wizard           | Limited         |
| 4     | 3–4 weeks    | FedRAMP + UX                       | Yes             |
| 5     | 3–4 weeks    | API + Deployment                   | Yes             |
