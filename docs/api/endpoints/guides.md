# User Guides API

Read-only access to the User Guides bundled into the running image (#784).

The guides are the task-oriented end-user documentation kept in the SPARC wiki
and shipped with the deployment, so what this API returns is versioned with the
image rather than fetched from the internet. The in-app Help Center is a thin
HTML client over the same `UserGuideLibrary` service, so the API and the app can
never disagree about what documentation this instance ships.

Intended for integrators embedding SPARC's guidance in their own portal, and for
checking which guides a given deployment carries.

## Authentication & authorization

A Bearer token is required. **Any authenticated user may read the guides** —
this is shipped product documentation carrying no record data, so it is not
boundary-scoped and not admin-gated. An unauthenticated caller gets `401`.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/v1/guides` | List every guide the image ships — slug, title, summary |
| `GET` | `/api/v1/guides/:slug` | One guide, with its rendered HTML |

> These endpoints are deliberately **absent from `/api/v1/available`**; see the
> note in `discovery_controller.rb`. Resolve a slug from the list endpoint
> rather than from discovery.

## List guides

```
GET /api/v1/guides
```

```json
{
  "data": [
    {
      "slug": "administration",
      "title": "Administration",
      "summary": "The Administration area is where Instance Admins manage people and instance-wide settings…"
    }
  ],
  "meta": { "count": 15 }
}
```

The summary is the guide's opening paragraph, for building an index without
fetching every page. Slugs are unique — the slug is what addresses a guide in
`show`.

## Show one guide

```
GET /api/v1/guides/:slug
```

```json
{
  "data": {
    "slug": "administration",
    "title": "Administration",
    "summary": "The Administration area is where Instance Admins manage people…",
    "html": "<h1>Administration</h1>…"
  }
}
```

`html` is the rendered guide body, which is the only field `show` adds over the
list. Images inside it resolve against the app's `/help/images/*` route.

An unknown slug returns `404` with `{"error": "Not found"}`.

> **Changed in v1.16.0 (#1036).** `show` previously returned the guide at the
> TOP level, with no `data` wrapper, while `index` and every other resource read
> in this API wrapped theirs. A client written against one response shape got
> `nil` here. It is now wrapped for consistency. Nothing in the application
> consumed the endpoint, so no in-app behaviour changed — but an external
> integrator written against the old shape must read `data`.
