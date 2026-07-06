# SPARC API Test Suite (issue #413 Phase 2)

Automated REST API test suite covering every endpoint in `/api/v1/`. Lives outside the Rails test pyramid (which is RSpec-based) because the spirit of issue #413 Phase 2 is *external, language-agnostic, contract-style validation* — the same kind a third-party integrator would run before depending on the API.

The coverage spine is [`docs/api/INVENTORY.md`](../../docs/api/INVENTORY.md). Every row in that table has at least one passing test in this suite; the `bin/api_inventory_check.rb` drift script gains a "covered by pytest" column once Phase 2 lands so future drift between code and tests is visible at a glance.

## Quick start

The suite is managed with [uv](https://docs.astral.sh/uv/) for reproducible dependency resolution and fast cold installs. `uv.lock` is committed; running `uv sync` produces a venv that exactly matches the lockfile and the version CI runs against.

### 1. Install

Either run natively with uv, or use the container — both produce identical environments.

**Native** (one-time uv install: `curl -LsSf https://astral.sh/uv/install.sh | sh`):

```bash
cd tests/api
uv sync --extra dev
```

**Containerized** (no local Python or uv install needed beyond Docker):

```bash
cd tests/api
docker build -t sparc-api-tests .
docker run --rm --network=host \
  --env-file .env \
  sparc-api-tests pytest
```

The container is built on `ghcr.io/astral-sh/uv:python3.12-bookworm-slim` (~80 MB) and runs `uv sync` at build time so the lockfile is baked in. `--network=host` lets the container reach a SPARC instance running on `localhost:3000`; for a Compose-deployed SPARC use `--network <compose-network>` instead.

### 2. Configure

The suite needs a running SPARC instance and tokens for two users (an admin and a non-admin). Either export them directly or drop them in `tests/api/.env` (gitignored):

```bash
# tests/api/.env
SPARC_TEST_BASE_URL=http://localhost:3000
SPARC_TEST_ADMIN_TOKEN=sparc_admin_token_value
SPARC_TEST_USER_TOKEN=sparc_user_token_value
```

Generate the tokens via the SPARC admin UI (Service Accounts → New) or in the Rails console:

```ruby
admin = User.find_by(admin: true)
puts ApiToken.generate!(user: admin, name: "phase2-admin").plaintext_token

user = User.find_by(email: "tester@example.com")
puts ApiToken.generate!(user: user, name: "phase2-user").plaintext_token
```

### 3. Run

All commands below are run from `tests/api/`. Prefix with `uv run` to use the synced environment without activating it.

```bash
# Full suite
uv run pytest

# Just one phase or controller
uv run pytest -m phase2
uv run pytest -m back_matter
uv run pytest -m discovery

# One module
uv run pytest test_discovery.py

# One test, with verbose output
uv run pytest test_discovery.py::TestDiscovery::test_admin_sees_full_inventory -v
```

`uv run pytest -n auto` parallelizes across cores via `pytest-xdist`. Watch for shared-state collisions if you do — most modules guard against this with per-module setup/teardown but a few are intentionally serial (e.g. admin-credential rotation).

### Expected results

A healthy instance runs the full suite in **~1–3 minutes** (network-bound). The
session janitor (#635) sweeps orphaned `phase2-*` resources at start and end, so
the **first run against a long-lived instance is slower** while it clears any
leftovers from prior interrupted runs. If `conftest.py` exits immediately with a
token/connection message, the fail-fast liveness check caught a bad token or an
unreachable instance — fix that before reading further failures.

## Configuration reference

| Variable | Default | Required | Purpose |
|---|---|---|---|
| `SPARC_TEST_BASE_URL` | _(none)_ | Yes | Root URL of the SPARC instance, no trailing slash |
| `SPARC_TEST_ADMIN_TOKEN` | _(none)_ | Yes | Bearer token for an admin user |
| `SPARC_TEST_USER_TOKEN` | _(none)_ | Yes | Bearer token for a non-admin user (read-level only) |
| `SPARC_TEST_RESET_DB` | `0` | No | Set to `1` to allow tests to recreate seed data between runs |

`pytest.ini_options` in [`pyproject.toml`](pyproject.toml) declares all the markers the suite uses so `--strict-markers` will catch typos.

## Coverage model

For every endpoint in `INVENTORY.md`, the suite includes at minimum:

| Test class | Asserts |
|---|---|
| `happy` | `2xx` status + response shape matches the doc-captured schema |
| `auth` | Request without token returns `401`; request with revoked / wrong token returns `401` |
| `authz` | Request from a token whose role lacks the required permission returns `403` (or `404` for resource-not-visible cases) |
| `validation` | Required-field-missing requests return `422` with the documented error envelope |
| `pagination` | Where the index endpoint supports them, paged + filtered requests return the expected slice |
| `idempotency` | Where applicable (`admin/refresh_credentials`, etc.), repeated identical requests return `unchanged` rather than re-mutating |

Not every test class applies to every endpoint (a `DELETE` doesn't paginate); the markers in `pyproject.toml` let you run "everything that's a 401-coverage test for back-matter" in one command.

## Layout

```
tests/api/
├── pyproject.toml          # dependencies + pytest config + markers
├── uv.lock                 # pinned transitive deps; reproducible installs
├── Dockerfile              # uv-based containerized runner
├── conftest.py             # shared fixtures (clients, smoke check, helpers)
├── README.md               # this file
├── fixtures/               # JSON request bodies, sample upload files
│   └── ...
├── test_discovery.py
├── test_ssp_documents.py
├── test_sar_documents.py
├── test_sap_documents.py
├── test_poam_documents.py
├── test_cdef_documents.py
├── test_profile_documents.py
├── test_back_matter_resources.py
├── test_authorization_boundaries.py
├── test_users.py
├── test_admin_credentials.py
├── test_authoritative_sources.py
├── test_federation_peers.py
├── test_baseline_parameters.py
├── test_control_catalogs.py
├── test_control_mappings.py
├── test_ksi_catalog.py
└── test_ksi_validations.py
```

One module per controller group. Modules import from `conftest.py` and share helpers; cross-module fixtures are deliberately rare so a single module remains debuggable on its own.

## CI integration

The GitHub Actions workflow at `.github/workflows/api-tests.yml` boots the SPARC Docker Compose stack, seeds the database, generates the admin and user tokens, and runs the full suite against the boot. See the workflow file for the exact command line.

Per-test results land in the run summary; a coverage delta against `INVENTORY.md` is computed in the final step (any inventory row not covered by at least one passing test is flagged as a regression).

## Self-containment

This is the deliberate Phase 2 contract: the suite must be runnable from a fresh checkout with **no external downloads** other than the Python deps in `pyproject.toml`. Every fixture body, sample upload file, and seed value lives under `tests/api/fixtures/` and is committed.

If a test needs OSCAL sample files larger than ~50KB, copy them into `fixtures/` rather than fetching from NIST or another live source — the test can verify checksums against a committed manifest.

## Related documentation

- [`docs/api/INVENTORY.md`](../../docs/api/INVENTORY.md) — coverage spine
- [`docs/api/SPARC-API-Review-and-Automated-Testing-Procedure.md`](../../docs/api/SPARC-API-Review-and-Automated-Testing-Procedure.md) — Phase 1 + Phase 2 procedure
- [`docs/api/README.md`](../../docs/api/README.md) — Postman collection (operator-facing alternative to this suite)
- [`docs/api/authentication.md`](../../docs/api/authentication.md), [`pagination.md`](../../docs/api/pagination.md), [`errors.md`](../../docs/api/errors.md) — API contracts these tests assert against
