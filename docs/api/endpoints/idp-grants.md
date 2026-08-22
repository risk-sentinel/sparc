# IdP Grants API

The unmatched-grant queue: entitlements an identity provider asked for that this
instance could not grant.

Added in [#860](https://github.com/risk-sentinel/sparc/issues/860).

## Why this exists

When SPARC maps IdP claims to roles, a grant may name an organization,
authorization boundary or role that does not exist here. The rule is that such a
grant is **recorded and surfaced, never created** — auto-creating would let the
identity provider define the estate, which inverts who controls it.

Recording without surfacing is only half of that, and the half nobody notices.
The user signs in successfully, holding less access than their directory says
they should have, and nothing about the login looks wrong. This endpoint is
where an administrator sees it.

## What happens to the user

They are provisioned and signed in normally, with whatever access **did**
resolve — possibly none. An account whose grants all failed to resolve holds no
memberships, so it sees only what any authenticated user sees, nothing
boundary-scoped. It is not an error state and needs no intervention beyond
creating the missing record.

**Nothing here needs clearing.** Every sign-in re-evaluates the claim, so once
the organization or boundary exists, the grant resolves by itself at that user's
next login. That is why this reads the audit trail rather than owning a table of
tasks: an unmatched grant is a current disagreement between the directory and
the estate, not a work item with a lifecycle.

## Base URL

```
https://sparc.example.com/api/v1/idp_grants
```

## Authorization

**Instance admin only.** The queue names organizations, boundaries and other
users' email addresses — the shape of the estate, which is not general-reader
information.

## Endpoints

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/v1/idp_grants/unmatched` | Grants refused in a recent window, with reasons and who they affected |

## `GET /api/v1/idp_grants/unmatched`

### Query parameters

| Parameter | Type | Default | Description |
| --- | --- | --- | --- |
| `days` | integer | `30` | How far back to look. Clamped to 1–365 |
| `user_id` | integer | — | Narrow to a single user |
| `page` | integer | `1` | Page number |
| `items` | integer | `50` | Page size |

### Response

```json
{
  "data": [
    {
      "id": 4821,
      "occurred_at": "2026-08-22T09:14:03Z",
      "user": { "id": 17, "email": "aisha@example.gov" },
      "grant": "sparc:boundary:acme:acme-prod:isso",
      "reason": "authorization boundary \"acme-prod\" not found"
    }
  ],
  "meta": {
    "current_page": 1,
    "total_count": 1,
    "window_days": 30,
    "summary": [
      {
        "reason": "authorization boundary \"acme-prod\" not found",
        "occurrences": 12,
        "affected_users": 4,
        "example_grant": "sparc:boundary:acme:acme-prod:isso"
      }
    ]
  }
}
```

### Reading `meta.summary`

Grouped by reason and ordered worst-first, so one missing boundary reads as one
problem rather than as twelve incidents.

**`affected_users` counts DISTINCT users; `occurrences` counts sign-ins.** One
person signing in five times is five occurrences and one affected user. Rank
your attention by `affected_users` — ordering by occurrences would put a single
persistent user above a misconfiguration locking out a whole team.

`role`, `organization` and `authorization_boundary` appear on a row when the
grant resolved but was refused on conflict (an administrator had already set a
different organization role), rather than failing to resolve at all.

### Status codes

| Code | Meaning |
| --- | --- |
| `200` | Success |
| `401` | No credentials |
| `403` | Authenticated but not an instance admin |

## Related

- Daily digest email to administrators, `UnmatchedGrantDigestJob` (no-op without SMTP)
- Admin screen: **Administration → IdP Grants**
- Configuration: `SPARC_OIDC_SYNC_MODE`, `SPARC_OIDC_GRANTS_CLAIM`,
  `SPARC_OIDC_GRANTS_PREFIX`, `SPARC_OIDC_INSTANCE_ROLES`
