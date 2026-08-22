# Entitlement Sync API

Inspect the IdP entitlement sync, and preview it before switching it on.

Added in [#860](https://github.com/risk-sentinel/sparc/issues/860).

## Why a dry run exists

The question an operator has before enabling `authoritative` is not "is my
configuration valid" but **"if I turn this on, what happens to my people?"** The
only honest answer computes the real plan, with the real resolver, against the
real estate — and then does not apply it.

`preview` therefore calls the same object the login path calls. A separate
simulation would be a second implementation that agrees with the first until the
day it does not, which is exactly when someone is relying on it.

## Base URL

```
https://sparc.example.com/api/v1/entitlement_sync
```

## Authorization

**Instance admin only.**

## Endpoints

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/v1/entitlement_sync` | Current configuration, and how much of the estate the sync owns |
| `POST` | `/api/v1/entitlement_sync/preview` | Compute a plan for one user without applying it |

## `GET /api/v1/entitlement_sync`

```json
{
  "data": {
    "mode": "bootstrap",
    "modes": ["off", "bootstrap", "authoritative"],
    "claim": "groups",
    "prefix": "sparc:",
    "instance_roles_allowed": ["global_viewer"],
    "max_revoke_pct": 0,
    "oidc_scopes": "openid profile email groups",
    "grants_scope_requested": true,
    "managed": { "user_roles": 42, "organization_memberships": 7 }
  }
}
```

**`grants_scope_requested`** is worth checking first when no grants arrive. A
scope is a *request*; the IdP decides what it releases, and the two halves are
configured in different places. The commonest support case is a correctly named
claim with the scope never asked for — the configuration looks right and nothing
comes through.

**`managed`** counts only memberships the sync created (`source: "idp"`). Those
are the only ones it can ever revoke.

## `POST /api/v1/entitlement_sync/preview`

### Request

```json
{
  "preview": {
    "user_id": 17,
    "mode": "authoritative",
    "grants": ["sparc:boundary:acme:acme-prod:isso", "sparc:org:acme:member"]
  }
}
```

The body is wrapped under `preview`, like every other `Api::V1` write. Fields
this endpoint does not accept are **refused with a 422 naming them**, not
silently discarded — the behaviour
[#995](https://github.com/risk-sentinel/sparc/issues/995) removed everywhere.

| Field | Required | Description |
| --- | --- | --- |
| `user_id` | yes | The user to compute a plan for |
| `mode` | no | Overrides the configured mode, so you can ask what `authoritative` *would* do while still running `bootstrap` |
| `grants` | no | The claim values. **See below — omitting it is not the same as sending `[]`** |

### Omitting `grants` is a different question from sending `[]`

This mirrors the sync itself, and the distinction is the one the whole feature
turns on:

- **`grants` omitted** — the claim was not in the token. SPARC changes nothing
  and reports why. A misconfigured claim name must never read as "this person
  has no entitlements."
- **`grants: []`** — the claim was present and empty. That is a real statement,
  and in `authoritative` mode it revokes.

Previewing them the same way would hide the misconfiguration this feature most
often meets.

### Response

```json
{
  "data": {
    "user": { "id": 17, "email": "aisha@example.gov" },
    "mode": "authoritative",
    "dry_run": true,
    "summary": "1 to add, 0 to update, 1 to revoke, 0 unchanged, 0 conflicting, 1 unmatched",
    "changes": [
      { "action": "add", "target": "user_role", "role": "isso",
        "organization": "acme", "authorization_boundary": "acme-prod" },
      { "action": "revoke", "target": "user_role", "role": "issm",
        "authorization_boundary": "acme-dev" }
    ],
    "unmatched": [
      { "grant": "sparc:boundary:acme:not-yet:isso",
        "reason": "authorization boundary \"not-yet\" not found" }
    ]
  }
}
```

### Change actions

| Action | Meaning |
| --- | --- |
| `add` | A membership the sync would create |
| `update` | An organization role the sync set before and would change |
| `revoke` | A membership the sync created and the claim no longer carries |
| `unchanged` | Already held; nothing to do |
| `conflict` | An administrator set a different organization role. **Reported, never overwritten** |

`error` appears when the sync would refuse outright (absent claim, unknown mode).
`blocked_reason` appears when `SPARC_OIDC_SYNC_MAX_REVOKE_PCT` would stop it.

### Status codes

| Code | Meaning |
| --- | --- |
| `200` | Plan computed. Nothing was written |
| `401` | No credentials |
| `403` | Authenticated but not an instance admin |
| `404` | Unknown `user_id` |
| `422` | Unknown `mode` |

## Related

- [IdP Grants API](idp-grants.md) — grants SPARC could not resolve
- Configuration: `SPARC_OIDC_SYNC_MODE`, `SPARC_OIDC_GRANTS_CLAIM`,
  `SPARC_OIDC_GRANTS_PREFIX`, `SPARC_OIDC_INSTANCE_ROLES`
