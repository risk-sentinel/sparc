# Roles API

RBAC role definitions and the permission sets every authorization check in the
application reads.

Added in [#1014](https://github.com/risk-sentinel/sparc/issues/1014). Before it,
roles could be created, edited and deleted only through a browser, so an
operator could not review or reproduce an instance's RBAC configuration
programmatically — which is exactly what an accreditation package has to show.
Found by the missing-endpoint axis of
[#995](https://github.com/risk-sentinel/sparc/issues/995).

## Two role systems, and this is the one that grants permissions

SPARC has a `Role`/`UserRole` system **and** a legacy membership roster. They
coexist, and #929 turned on telling them apart. A role here carries permissions
and grants them wherever it is assigned; a roster entry does not.

**Instance Admin is not a role.** It is the `users.admin` boolean, so it cannot
be created or granted here.

## Base URL

```
https://sparc.example.com/api/v1/roles
```

## Authorization

**Instance admin only**, reads included. The role catalog is the map of who can
do what.

## Scope

Every role is either `instance` (global) or `authorization_boundary`
(granted per boundary). `GET /api/v1/roles?scope=instance` narrows the list.

## Endpoints

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/roles` | List roles, `?scope=` filterable |
| `POST` | `/api/v1/roles` | Create a role and its permission set |
| `GET` | `/api/v1/roles/:id` | Show a role, its granted permissions, and the full key list |
| `PATCH`/`PUT` | `/api/v1/roles/:id` | Update attributes and/or replace the permission set |
| `DELETE` | `/api/v1/roles/:id` | Delete a role that is not assigned to anyone |

### Permissions

`permissions` is a map of `"resource.action"` to boolean:

```json
{
  "role": {
    "name": "custom_reviewer",
    "display_name": "Custom Reviewer",
    "scope": "authorization_boundary",
    "permissions": {
      "ssp.read": true,
      "ssp.write": false
    }
  }
}
```

Both real JSON booleans and the web form's `"1"` are accepted.

**On update the permission set is replaced wholesale**, matching the web form:
the request states the role's complete permission set, so **a key omitted is a
key revoked**. A partial merge would leave no way to express "remove this
permission". Omit the `permissions` key entirely to leave the set untouched.

A key that is not in `Role::PERMISSION_KEYS` is **ignored rather than refused** —
the map is rebuilt from the canonical list, so a permission the application does
not enforce cannot be written, and a stale key from an older instance should not
fail an otherwise valid request. That covers `catalogs.read`, `profiles.read` and
`mappings.read`, removed in v1.17.2: reading the control library needs only a
valid token, so the keys restricted nothing. `available_permissions` on the show response is
the current canonical list.

This is the one place `permit_strictly`'s refusal does not apply, and it is
deliberate: the guarantee here is stronger, because an unrecognised key cannot
reach the record at all.

#### Response Body

```json
{
  "data": {
    "id": 7,
    "name": "custom_reviewer",
    "display_name": "Custom Reviewer",
    "scope": "authorization_boundary",
    "sort_order": 42,
    "assignment_count": 3,
    "description": "Reviews things",
    "permissions": ["ssp.read"],
    "available_permissions": ["catalogs.write", "catalogs.approve", "..."],
    "built_in": false,
    "shipped_defaults": null,
    "admin_overrides": [],
    "created_at": "2026-08-20T14:22:18Z",
    "updated_at": "2026-08-20T14:22:18Z"
  }
}
```

`permissions` lists the **granted** keys only, so a reader sees what the role
does rather than scanning every boolean for the true ones.

### Built-in roles: shipped defaults and administrator overrides

Added in [#1259](https://github.com/risk-sentinel/sparc/issues/1259). The roles
SPARC ships (`built_in: true`) each have a **shipped default** for every
permission key and for `display_name`, `description`, `sort_order` and `scope`.
The show response reports them:

```json
{
  "data": {
    "name": "view_only",
    "built_in": true,
    "shipped_defaults": {
      "display_name": "View Only",
      "description": "Read-only access to assigned authorization boundary artifacts. ...",
      "sort_order": 29,
      "scope": "authorization_boundary",
      "permissions": ["authorization_boundaries.read", "cdef.read", "..."]
    },
    "admin_overrides": ["ssp.write"]
  }
}
```

`admin_overrides` lists the keys and attributes an administrator has set to
something other than the shipped default. **An upgrade never changes them**:
the roles seed section brings every other value up to the new release's default
and leaves these exactly as set, writing an audit event for each value it
changes (`role_default_applied`) and for each shipped change it skipped because
of an override (`role_default_skipped`).

An update records the choice for each value it sets:

- a permission key (when `permissions` is sent, every key is set) or attribute
  whose new value **differs** from the shipped default is added to
  `admin_overrides`;
- one set **equal** to the shipped default is removed from it. That is how to
  reset a value to its default: send the value in `shipped_defaults`. From then
  on it follows the shipped default again.

An update that omits `permissions` leaves the permission overrides untouched.
`admin_overrides` itself cannot be written directly. A role an administrator
created has `built_in: false`, `shipped_defaults: null` and no overrides; the
seeds never read or write it.

### DELETE /api/v1/roles/:id

Refuses with `422` while any assignment remains. Deleting an assigned role would
strip access from every holder at once, with nothing recording who lost what —
remove the assignments first.

## Status Codes

| Status | Description |
|---|---|
| `200 OK` | Read, update, or delete succeeded |
| `201 Created` | Role created |
| `401 Unauthorized` | Missing or invalid Bearer token |
| `403 Forbidden` | Caller is not an instance admin |
| `404 Not Found` | No role matches the id |
| `422 Unprocessable Entity` | Validation failed, the role is still assigned, or the body carried a field this endpoint does not accept |

## Audit

| Action | When |
|---|---|
| `role_created` | Role created |
| `role_updated` | Attributes or permissions changed |
| `role_deleted` | Role deleted |

## NIST 800-53 Controls

- **AC-2** Account Management · **AC-3** Access Enforcement · **AC-6** Least Privilege
- **AU-12** Audit Record Generation
