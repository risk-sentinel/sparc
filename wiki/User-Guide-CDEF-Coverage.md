# CDEF Coverage

Answers the question a team standing up a new authorization boundary cannot
otherwise answer without reading their Terraform by eye: **which Component
Definitions do we need?**

Upload the Terraform the boundary is built from and SPARC reports, service by
service, whether to adopt a published AWS Labs CDEF, keep one of your own,
author a missing one, or retire one nothing uses.

## Your state file is not stored

This matters enough to say first.

Terraform state contains secrets in plaintext — database passwords, private
keys, session tokens, account identifiers. SPARC reads only three things about
each resource: whether it is managed, its **type** (for example
`aws_db_instance`), and how many of them there are. Resource attributes are
never read.

The file you upload is parsed while the request is handled and then discarded.
It is never attached to a record and never written to storage. If you save the
analysis, what is written is the list of services, their resource type names and
counts, the verdicts, and each file's name and SHA-256 checksum — enough to
recognise the same state later, nothing that could expose a credential.

## Where to find it

- **From an authorization boundary** — open the boundary and choose
  **CDEF Coverage**. The analysis is pre-attached to that boundary, which is
  usually what you want.
- **From the CDEF area** — `/cdef_coverage` lists every saved analysis, and
  **New analysis** starts one that need not belong to any boundary.

## What to upload

Either format, and both together if it helps:

- **Terraform state** (`.tfstate`) — what is deployed now.
- **Plan JSON** — produced by `terraform show -json plan.tfplan`. This describes
  what *will* exist, so you can assess a boundary before you build it. A
  resource the plan only destroys is not counted; a resource being replaced is.

**Upload every state that makes up the boundary.** A real boundary usually spans
several — one for the compute stack, another for configuration and logging.
Coverage is calculated across everything you upload together, so analysing one
state on its own reports the services defined in the others as unused.

## Reading the report

| Verdict | What it means | What to do |
|---|---|---|
| **Adopt AWS Labs CDEF** | Deployed, and AWS publishes a Component Definition | Use theirs rather than writing your own |
| **Keep custom CDEF** | Deployed, and only your CDEF covers it | Keep maintaining it |
| **Needs a CDEF** | Deployed, with no Component Definition anywhere | This is the work |
| **Unused CDEF** | You maintain one, but nothing you uploaded deploys it | Retire it, or check you uploaded every state |

Only your own CDEFs are ever marked unused. An AWS Labs one that nothing deploys
came from upstream and costs you nothing to keep.

### "inferred" findings

A finding badged **inferred** is one SPARC worked out from the resource type's
name rather than recognising the service. `azurerm_storage_account` becomes
`azurerm:storage`, for instance. The badge and the colon are there so you can
tell a derived name from one SPARC actually knows.

These are still reported as gaps. A boundary running on a cloud SPARC has no
mapping rules for yet would otherwise show no gaps at all, and no gaps reads as
full coverage.

The report also lists the raw resource types nothing matched, which is what lets
the mapping rules be extended from what people really deploy.

### Components that are never in Terraform

Some things legitimately have a CDEF but never appear in any state — a container
sidecar, a CI/CD pipeline. Left alone they would be flagged unused on every
single run. An administrator can mark those so they stay marked as kept, and can
record that a particular CDEF of yours covers a particular service when its name
does not make that obvious. SPARC never guesses that from a CDEF's title.

## Saving

Analysing saves nothing. Read the report, and if it is worth keeping, choose
**Save analysis** — optionally attaching it to a boundary so you keep a history
of what that boundary needed. You are not asked to select your files again: the
result carries forward in a short-lived signed token, so the Terraform is not
read a second time and is still never stored.

Saved analyses are listed at `/cdef_coverage`, and each records which files were
analysed by name and checksum.

## For automation

The same capability is available through the API — see
[API Reference](API-Reference) and `docs/api/endpoints/cdef-coverage.md`.
`POST /api/v1/cdef_coverage/analyze` returns the report plus a token you can
pass to `POST /api/v1/cdef_coverage/runs` to save it without uploading twice.
