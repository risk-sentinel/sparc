# Organizations API

Organizations scope authorization boundaries and documents, and their
membership decides who can see what.

Added in [#1012](https://github.com/risk-sentinel/sparc/issues/1012). Before it,
creating an organization, assigning a boundary to it and adding or removing a
member were all browser-only. Found by the missing-endpoint axis of
[#995](https://github.com/risk-sentinel/sparc/issues/995).

## Base URL

```
https://sparc.example.com/api/v1/organizations
```

Addressable by **slug** (what the web routes use) or numeric id.

## Authorization

**Instance admin only**, reads included.

## There is no DELETE

Organizations are **never hard-deleted**. They are deactivated and reactivated,
preserving the UUID for audit traceability — a boundary or document that
referenced the organization must still resolve. `POST …/deactivate` is the
closest thing to a delete.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/organizations` | List organizations, `?q=` searchable |
| `POST` | `/api/v1/organizations` | Create one |
| `GET` | `/api/v1/organizations/:id` | Show one, with member and boundary counts |
| `PATCH`/`PUT` | `/api/v1/organizations/:id` | Update attributes |
| `POST` | `/api/v1/organizations/:id/deactivate` | Deactivate (never deletes) |
| `POST` | `/api/v1/organizations/:id/reactivate` | Reactivate |
| `POST` | `/api/v1/organizations/:id/boundaries` | Assign a boundary, or move it from another organization |
| `GET` | `/api/v1/organizations/:id/members` | List membership |
| `POST` | `/api/v1/organizations/:id/members` | Add a member with a role |
| `DELETE` | `/api/v1/organizations/:id/members/:membership_id` | Remove a member |

### POST /api/v1/organizations

| Field | Type | Description |
|---|---|---|
| `name` | string | Required |
| `description` | string | |
| `address` | string | |
| `contact_person` | string | |
| `contact_email` | string | |

Any other field is refused with `422`.

### POST /api/v1/organizations/:id/boundaries

```json
{ "authorization_boundary_id": 42 }
```

Assigns an unattached boundary, or **moves** one that already belongs to another
organization. The response says which happened:

```json
{
  "data": {
    "organization_id": 7,
    "authorization_boundary_id": 42,
    "moved_from_organization_id": 3,
    "moved": true
  }
}
```

Authorization for assign-versus-move is enforced by `BoundaryOrganizationAssigner`
— the same object the web screen uses — so the matrix lives in one place rather
than being restated per surface (AC-3).

### Membership

```json
{ "user_id": 12, "role": "org_admin" }
```

Valid roles come from `OrganizationMembership.available_roles`, which is
configurable through `SPARC_ORGANIZATION_ROLES`. A role outside that set is
refused with `422` and nobody is added.

## Status Codes

| Status | Description |
|---|---|
| `200 OK` | Read, update, lifecycle action, assignment or removal succeeded |
| `201 Created` | Organization created, or member added |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller is not an instance admin |
| `404 Not Found` | No such organization, boundary, membership or user |
| `422 Unprocessable Entity` | Validation failed, or the body carried a field this endpoint does not accept |

## Audit

| Action | When |
|---|---|
| `organization_created` / `organization_updated` | Create / update |
| `organization_deactivated` / `organization_reactivated` | Lifecycle |
| `organization_boundary_assigned` | Assign or move; metadata records the previous organization |
| `organization_member_added` / `organization_member_removed` | Membership; metadata records the target user and role |

## NIST 800-53 Controls

- **AC-2** Account Management — membership is account management
- **AC-3** Access Enforcement · **AU-12** Audit Record Generation
