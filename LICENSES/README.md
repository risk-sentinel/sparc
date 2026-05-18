# SPARC License Texts

Canonical text for every license referenced by SPARC's CycloneDX SBOM
inventory. Fetched from the SPDX license-list-data corpus by
`bin/rails licenses:fetch` (see `lib/tasks/licenses.rake`).

Generated: `2026-05-18T00:45:18Z`.

## Component count per license

| File | Components | Notes |
| --- | ---: | --- |
| [`MIT.txt`](MIT.txt) | 166 | SPDX canonical |
| [`Ruby.txt`](Ruby.txt) | 95 | SPDX canonical |
| [`GPL-2.0-or-later.txt`](GPL-2.0-or-later.txt) | 26 | SPDX canonical |
| [`BSD-3-Clause.txt`](BSD-3-Clause.txt) | 23 | SPDX canonical |
| [`Apache-2.0.txt`](Apache-2.0.txt) | 18 | SPDX canonical |
| [`BSD-2-Clause.txt`](BSD-2-Clause.txt) | 18 | SPDX canonical |
| [`GPL-2.0-only.txt`](GPL-2.0-only.txt) | 15 | SPDX canonical |
| [`GPL-3.0-or-later.txt`](GPL-3.0-or-later.txt) | 14 | SPDX canonical |
| [`LGPL-2.1-only.txt`](LGPL-2.1-only.txt) | 5 | SPDX canonical |
| [`LGPL-2.1-or-later.txt`](LGPL-2.1-or-later.txt) | 5 | SPDX canonical |
| [`LGPL-2.0-or-later.txt`](LGPL-2.0-or-later.txt) | 4 | SPDX canonical |
| [`GPL-1.0-or-later.txt`](GPL-1.0-or-later.txt) | 4 | SPDX canonical |
| [`LGPL-3.0-or-later.txt`](LGPL-3.0-or-later.txt) | 3 | SPDX canonical |
| [`CC0-1.0.txt`](CC0-1.0.txt) | 2 | SPDX canonical |
| [`PostgreSQL.txt`](PostgreSQL.txt) | 2 | SPDX canonical |
| [`BSD-4-Clause.txt`](BSD-4-Clause.txt) | 2 | SPDX canonical |
| [`BSD-3-Clause-Cambridge-WITH-exception.txt`](BSD-3-Clause-Cambridge-WITH-exception.txt) | 1 | non-SPDX; manually curated; missing — fetch failed |
| [`Zlib.txt`](Zlib.txt) | 1 | SPDX canonical |
| [`OLDAP-2.8.txt`](OLDAP-2.8.txt) | 1 | SPDX canonical |
| [`Sleepycat.txt`](Sleepycat.txt) | 1 | SPDX canonical |
| [`GFDL-1.3-no-invariants-or-later.txt`](GFDL-1.3-no-invariants-or-later.txt) | 1 | SPDX canonical |
| [`LGPL-3.0-only.txt`](LGPL-3.0-only.txt) | 1 | SPDX canonical |
| [`GPL-3.0-only.txt`](GPL-3.0-only.txt) | 1 | SPDX canonical |
| [`Brakeman-Public-Use-License.txt`](Brakeman-Public-Use-License.txt) | 1 | non-SPDX; manually curated; missing — fetch failed |

## How to refresh

1. Download a fresh `license-inventory.json` from the latest Security Scanning CI run:
   `gh run download <run-id> --name license-inventory`
2. `bin/rails 'licenses:fetch[license-inventory.json]'`
3. Commit any new `LICENSES/*.txt` files and the updated `README.md`.

Non-SPDX entries (Brakeman Public Use License, etc.) require manual
curation -- copy the upstream text into the file path listed above.
