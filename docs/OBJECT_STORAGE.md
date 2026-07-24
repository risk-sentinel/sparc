# Object storage — operator guide

**Applies from v1.13.1 (#785 Pass 2.1).** NIST 800-53 CP-9, SI-12.

Where SPARC keeps uploaded blobs — document files, evidence, artifact versions, avatars —
and how to point it at the right place with one variable.

## One variable

```
SPARC_STORAGE_URL=s3://my-bucket            # region from AWS_REGION
SPARC_STORAGE_URL=s3://my-bucket?region=us-east-1
(unset)                                     # local disk (dev)
```

The **scheme picks the provider**; `storage.yml` derives the Active Storage backend from
it, the same way `DATABASE_URL` drives the database. On AWS with an IAM task role, the
common case is one line — `SPARC_STORAGE_URL=s3://my-bucket` — with region from the
Terraform-set `AWS_REGION` and credentials from the role (nothing else to set).

### Region is resolved, not embedded

An S3 bucket name doesn't carry a region, so region resolves by precedence:

**URL `?region=` → `AWS_REGION` → `us-east-1`.**

`AWS_REGION` is the SDK-wide region variable and is usually already set (Terraform injects
it), so most deployments never specify region in the URL.

## Production refuses local disk

The single most damaging storage mistake is deploying to ECS/EKS on local disk: uploads
work, then a redeploy silently eats them, because the container filesystem is ephemeral.

**So production hard-fails at boot if object storage resolves to local disk**, with a clear
message telling you to set `SPARC_STORAGE_URL`. This is stronger than the database-TLS
posture check (which warns) because silent data loss is worse than an
encrypted-but-unauthenticated connection.

Every boot logs the resolved backend, so you can see where blobs go:

```
[SPARC] Object storage: amazon bucket=my-bucket region=us-east-1.
```

### If you really do use durable local storage

Single-node or mounted-volume deployments that genuinely want local disk acknowledge it:

```
SPARC_ALLOW_LOCAL_STORAGE=true
```

Then production boots on local disk with a warning instead of failing. Use this only when a
persistent volume backs `storage/` — otherwise you are opting into data loss.

## Credentials stay separate

The URL says *where*, not *how to authenticate*:

- **AWS + IAM task role** (ECS/EKS) — set nothing; the SDK uses the role.
- **AWS access keys** — `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` (or Rails credentials).

## Backward compatibility

With `SPARC_STORAGE_URL` unset, the legacy `ACTIVE_STORAGE_SERVICE` + `AWS_BUCKET` path
works unchanged — this reduces what you must *set*, not what works. A deployment already
using `ACTIVE_STORAGE_SERVICE=amazon` + `AWS_BUCKET` needs no change.

> **Default change worth noting:** with nothing set, storage now resolves to **local**
> (previously `production.rb` defaulted to `:amazon`). Combined with the hard-fail above,
> a production deploy that sets neither `SPARC_STORAGE_URL` nor `ACTIVE_STORAGE_SERVICE`
> now fails fast with a clear message instead of silently selecting an unconfigured S3.

## Providers

S3 and local are supported today (only `aws-sdk-s3` is bundled). The URL scheme is designed
to extend to `azure://` and `gcs://` once their gems and `storage.yml` services are added —
Azure addresses by account name and GCS by project/bucket, neither of which needs a region,
so only S3 ever carries the region concern.

## Variables

| Variable | Default | Notes |
|---|---|---|
| `SPARC_STORAGE_URL` | unset → local | `s3://bucket[?region=X]`. Preferred |
| `SPARC_ALLOW_LOCAL_STORAGE` | false | Acknowledge production local disk (else hard-fail) |
| `ACTIVE_STORAGE_SERVICE` | local | Legacy fallback when `SPARC_STORAGE_URL` unset |
| `AWS_BUCKET` | (none) | Legacy fallback bucket |
| `AWS_REGION` | us-east-1 | SDK-wide region; also the storage region fallback |
