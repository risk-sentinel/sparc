# ATO package — demo output (#836)

> **DEMO/SAMPLE DATA ONLY.** Fictional content, for testing and demonstration.
> No real organizations, systems or personnel are represented.

What `AtoPackageExportService` produces for a boundary: every authorization
document, in **all three OSCAL serializations**, plus a manifest describing
exactly what is inside.

## Contents

| File | What it is |
|---|---|
| `ato-package.zip` | The package as a user downloads it — 16 files, 5 documents × 3 serializations, plus the manifest |
| `manifest.json` | The same manifest, loose, so the package contents are reviewable in a diff without unzipping |
| `cdef-example.{json,yaml,xml}` | One document in all three serializations, for comparison at a readable size |

The zip holds `ssp`, `sap`, `sar`, `poam-1` and one `cdef`, each as `.json`,
`.yaml` and `.xml`.

## Why the zip rather than every file loose

The extracted package is **3.2 MB** — the SSP alone is 778 KB of JSON, and
`samples/` in total was 204 KB before this. Committing it unpacked would make
demo data the largest thing in the repository.

The zip is the artifact a user actually downloads, so it is the honest thing to
ship. The manifest and one worked document are committed loose so a reviewer can
read the shape without extracting anything.

## The manifest invariant (#828)

The manifest lists exactly the files in the archive — never more. It used to be
built from the boundary's associations while the archive was built from exports
that could fail, so a failed export left the manifest advertising a file that
was not there, with only a log line as evidence. A package that claims to
contain an SSP and does not is worse than an export that fails outright, because
nothing signals the loss.

The fix was structural: exports run first, and both the archive and the manifest
derive from the **same results**, so they cannot disagree.
`spec/integration/ato_package_export_spec.rb` asserts it in both directions.

## Regenerating

```ruby
# bin/rails runner
boundary = AuthorizationBoundary.find_by(name: "Cloud Web Application ATO")
File.binwrite("ato-package.zip", AtoPackageExportService.new(boundary).generate_zip)
```

Generated from the demo boundary with `@mitre/saf`-independent code paths;
every document is schema-validated by the integration spec, XML included (#827).
