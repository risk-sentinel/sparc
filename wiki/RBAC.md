# Role-Based Access Control (RBAC)

## Overview

SPARC implements a granular Role-Based Access Control system with **29 roles** aligned with [NIST SP 800-37 Rev. 2](https://csrc.nist.gov/publications/detail/sp/800-37/rev-2/final) (Risk Management Framework). The system is designed to mirror real-world security authorization workflows, ensuring that each user in the compliance lifecycle has precisely the access they need and nothing more.

Authorization is enforced through **three layers**, evaluated in order:

| Layer | Mechanism | Scope |
|-------|-----------|-------|
| 1. Instance Admin | Boolean flag on `User` model | Global bypass -- all checks pass |
| 2. Role-based | `has_role?(role_name, project_id:)` | Structural access by job function |
| 3. Permission-based | `has_permission?(key, project_id:)` | Granular control over specific resources |

**Backward Compatibility:** All authorization checks are no-ops when `SparcConfig.any_auth_enabled?` returns `false`. This allows existing deployments to upgrade without breaking changes until RBAC is explicitly enabled.

---

## Instance Admin

Instance Admin is a **boolean column on the User model**, not a role. It provides unrestricted access to the entire SPARC instance.

- Bypasses ALL authorization checks across all projects and resources.
- The first Instance Admin account is bootstrapped during `db:seed` with a randomly generated 16-character password.
- The bootstrapped admin **must change their password on first login**.
- Instance Admin status can only be granted by another Instance Admin through the admin interface.

> Instance Admin is intended for platform operators and initial setup only. Day-to-day users should be assigned appropriate roles instead.

---

## Role Scoping

SPARC roles are divided into two categories based on their scope:

- **Instance-Scoped Roles** (10 roles) -- Apply globally across all projects. Stored with `project_id = NULL` in the `user_roles` table.
- **Project-Scoped Roles** (19 roles) -- Apply only to the specific project they are assigned to. Stored with a `project_id` value in the `user_roles` table.

A single user can hold:
- Multiple instance-scoped roles simultaneously.
- Different project-scoped roles across different projects.
- A combination of instance-scoped and project-scoped roles.

---

## Permission Keys

SPARC defines **20 permission keys** across 10 resource areas. Each key controls either read or write access to a specific resource type.

| Resource | Read Key | Write Key |
|----------|----------|-----------|
| Catalogs | `catalogs.read` | `catalogs.write` |
| Profiles | `profiles.read` | `profiles.write` |
| Projects | `projects.read` | `projects.write` |
| Project Members | -- | `projects.manage_members` |
| SSP | `ssp.read` | `ssp.write` |
| SAR | `sar.read` | `sar.write` |
| SAP | `sap.read` | `sap.write` |
| POA&M | `poam.read` | `poam.write` |
| CDEF | `cdef.read` | `cdef.write` |
| Evidence | `evidence.read` | `evidence.write` |
| Mappings | `mappings.read` | `mappings.write` |

---

## Permission Resolution

When a permission check is performed, the system resolves the effective permission set by combining both instance-scoped and project-scoped roles:

```
Effective permissions = permissions from user_roles
                        WHERE project_id IN (target_project_id, NULL)
```

This means:
1. Instance-scoped role permissions always apply, regardless of the target project.
2. Project-scoped role permissions apply only when the target project matches.
3. If a user has multiple roles (instance or project), their permissions are the **union** of all granted permissions.

### Example

A user with the **Global Viewer** instance role and the **ISSO** project role on Project A would have:
- Read access to all resources globally (from Global Viewer).
- Read/write access to SSP, SAR, SAP, POA&M, and Evidence on Project A (from ISSO).
- Only read access on Project B (from Global Viewer alone).

---

## Instance-Scoped Roles

These 10 roles apply across the entire SPARC instance and are not tied to any specific project.

### Policy Manager

Full CRUD on catalogs and profiles. Controls enterprise baselines and organizational policy overlays.

### Global Viewer

Read-only access to all shared catalogs, profiles, and organizational resources. Intended for auditors and oversight staff who need visibility without modification rights.

### Senior Accountable Official

Risk oversight role with read access to all resources. Responsible for ensuring organizational risk posture aligns with mission objectives.

### Senior Agency Official for Privacy (SAOP)

Privacy risk management role. Read access to all resources for reviewing privacy controls and ensuring PII protections are adequate.

### Head of Agency / CEO

Ultimate accountability for the organization's security program. Read access to all resources.

### Risk Executive

Organization-wide risk tolerance and strategy. Read access to all resources for making enterprise risk decisions.

### Chief Information Officer (CIO)

Oversees the IT security program. Read access to all resources for strategic technology and security oversight.

### Chief Acquisition Officer

Supply chain security oversight. Read access to catalogs, profiles, projects, CDEFs, evidence, and mappings. Does not have access to SSP, SAR, SAP, or POA&M resources.

### FedRAMP PMO

FedRAMP program management office oversight. Read access to all resources for monitoring FedRAMP authorization activities.

### Joint Authorization Board (JAB)

Provisional Authority to Operate (P-ATO) reviews. Read access to all resources for evaluating cloud service provider security packages.

---

### Instance-Scoped Permission Matrix

| Role | Catalogs | Profiles | Projects | SSP | SAR | SAP | POA&M | CDEF | Evidence | Mappings |
|------|----------|----------|----------|-----|-----|-----|-------|------|----------|----------|
| Policy Manager | R/W | R/W | R | R | R | R | R | R | R | R/W |
| Global Viewer | R | R | R | R | R | R | R | R | R | R |
| Senior Accountable Official | R | R | R | R | R | R | R | R | R | R |
| SAOP | R | R | R | R | R | R | R | R | R | R |
| Head of Agency / CEO | R | R | R | R | R | R | R | R | R | R |
| Risk Executive | R | R | R | R | R | R | R | R | R | R |
| CIO | R | R | R | R | R | R | R | R | R | R |
| Chief Acquisition Officer | R | R | R | - | - | - | - | R | R | R |
| FedRAMP PMO | R | R | R | R | R | R | R | R | R | R |
| JAB | R | R | R | R | R | R | R | R | R | R |

---

## Project-Scoped Roles

These 19 roles are assigned per-project and only grant access within the context of that project.

### Authorizing Official (AO)

Accepts risk and issues Authority to Operate (ATO) decisions. Has read access to project documentation and write access to POA&M items to track risk acceptance.

### Agency Authorizing Official

Agency-specific ATO authority. Same permission set as the Authorizing Official role, scoped to agency-level authorization decisions.

### System Owner (SO/ISO)

Owns the information system. Broad read/write access to SSP, POA&M, CDEF, and evidence to maintain the system's security posture documentation.

### CISO

Chief Information Security Officer. Strategic oversight with read access across all project resources. Does not have direct write access to project artifacts.

### ISSM (Information System Security Manager)

Oversees the security posture of the system. Read/write access to SSP, POA&M, and evidence. Read access to SAR, SAP, CDEF, and mappings.

### ISSO (Information System Security Officer)

Day-to-day security operations. Broadest write access among project roles -- read/write to SSP, SAR, SAP, POA&M, and evidence.

### Cloud Service Provider (CSP)

SSP and CDEF implementation for cloud systems. Read/write access to SSP, POA&M, CDEF, and evidence. Read access to SAR, SAP, and mappings.

### Assessor / 3PAO

Independent assessment role (Third Party Assessment Organization). Read/write access to SAR and SAP. Read access to SSP, POA&M, CDEF, evidence, and mappings.

### Common Control Provider

Manages shared/inherited controls. Read/write access to SSP, CDEF, and evidence.

### System Architect / Engineer

Security design and architecture. Read/write access to SSP and CDEF. Read access to evidence.

### Component Supplier / Product Engineer

Builds reusable security components. Read/write access to CDEF and evidence.

### System Operator / Administrator

Daily system operations. Read access to SSP and POA&M. Read/write access to evidence.

### Information Owner / Steward

Data governance and classification. Read access to SSP, CDEF, and evidence.

### Vendor Dependency Manager

Tracks vendor security dependencies. Read access to SSP. Read/write access to CDEF and evidence.

### Solution Evaluator

Evaluates tools and services for security fitness. Read access to SSP, SAR, CDEF, and evidence.

### Project Member

General project contributor. Read/write access to SSP, POA&M, CDEF, and evidence. Read access to profiles.

### SPARC SME (Subject Matter Expert)

Broad expertise across the SPARC platform. Read access to catalogs, profiles, and mappings. Read/write access to SSP, SAR, SAP, POA&M, CDEF, and evidence.

### Evidence Integration Engineer

Manages the evidence lifecycle including collection, validation, and linking to controls. Read access to catalogs, profiles, SSP, SAP, POA&M, CDEF, and mappings. Read/write access to SAR and evidence.

### View Only

Read-only project access for stakeholders who need visibility but no modification rights. Read access to projects, SSP, SAR, POA&M, CDEF, and evidence.

---

### Project-Scoped Permission Matrix

| Role | Catalogs | Profiles | Projects | SSP | SAR | SAP | POA&M | CDEF | Evidence | Mappings |
|------|----------|----------|----------|-----|-----|-----|-------|------|----------|----------|
| Authorizing Official (AO) | - | - | R | R | R | R | R/W | R | R | R |
| Agency Authorizing Official | - | - | R | R | R | R | R/W | R | R | R |
| System Owner (SO/ISO) | - | - | R | R/W | R | R | R/W | R/W | R/W | R |
| CISO | R | R | R | R | R | R | R | R | R | R |
| ISSM | - | - | R | R/W | R | R | R/W | R | R/W | R |
| ISSO | - | - | R | R/W | R/W | R/W | R/W | R | R/W | R |
| CSP | - | - | R | R/W | R | R | R/W | R/W | R/W | R |
| Assessor / 3PAO | - | - | R | R | R/W | R/W | R | R | R | R |
| Common Control Provider | - | - | R | R/W | - | - | - | R/W | R/W | - |
| System Architect / Engineer | - | - | R | R/W | - | - | - | R/W | R | - |
| Component Supplier / Product Engineer | - | - | R | - | - | - | - | R/W | R/W | - |
| System Operator / Administrator | - | - | R | R | - | - | R | R | R/W | - |
| Information Owner / Steward | - | - | R | R | - | - | - | R | R | - |
| Vendor Dependency Manager | - | - | R | R | - | - | - | R/W | R/W | - |
| Solution Evaluator | - | - | R | R | R | - | - | R | R | - |
| Project Member | - | R | R | R/W | - | - | R/W | R/W | R/W | - |
| SPARC SME | R | R | R | R/W | R/W | R/W | R/W | R/W | R/W | R |
| Evidence Integration Engineer | R | R | R | R | R/W | R | R | R | R/W | R |
| View Only | - | - | R | R | R | - | R | R | R | - |

---

## Authorization Enforcement

### Controller Methods

Authorization is enforced in controllers using three methods, each corresponding to one of the three authorization layers:

```ruby
# Layer 1: Require Instance Admin (boolean flag check)
authorize_admin!

# Layer 2: Require a specific role (instance or project-scoped)
authorize_role!("isso", project_id: @project.id)

# Layer 3: Require a specific permission (most granular)
authorize_permission!("ssp.write", project_id: @project.id)
```

### Failure Handling

All three methods raise `Authorization::NotAuthorizedError` on failure. When this exception is raised:

1. An `authorization_failure` audit event is logged with details about the user, requested resource, and missing authorization.
2. The user receives an appropriate HTTP error response (typically 403 Forbidden).

### Usage Guidelines

| Use Case | Method |
|----------|--------|
| Admin-only settings pages | `authorize_admin!` |
| Pages restricted to a job function (e.g., only assessors) | `authorize_role!` |
| Actions on specific resource types (e.g., editing an SSP) | `authorize_permission!` |

For most controller actions, `authorize_permission!` is the preferred method because it provides the most granular control and automatically accounts for both instance-scoped and project-scoped roles.

---

## Related Issues and Pull Requests

| Reference | Description |
|-----------|-------------|
| PR #73 | Initial authentication, users, roles, and registration |
| PR #112 | RBAC Admin Screens (Issues #92, #93, #94) |
| PR #115 | RBAC enforcement, summary tiles, full role coverage |
| Issue #96 | Added SPARC SME and Evidence Integration Engineer roles |
| Issue #99 | Restricted catalog/baseline edit to Policy Manager and Admin |
| `docs/groups_users.md` | Foundation RBAC reference document |
