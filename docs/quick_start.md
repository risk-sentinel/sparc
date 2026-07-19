# Quick Start

## Docker (Recommended)

```bash
git clone https://github.com/risk-sentinel/sparc.git
cd sparc
docker compose up --build
```

Open [local host](http://localhost:3000). Then seed the NIST catalogs:

```bash
docker compose exec web bin/rails db:seed
```

See [Docker Deployment](docs/DOCKER.md) for full details.

## Local Development

```bash
git clone https://github.com/risk-sentinel/sparc.git
cd sparc
bundle install
bin/rails db:create db:migrate db:seed
bin/rails server
```

**Prerequisites:** Ruby 3.4.4, PostgreSQL 15+, Bundler

Background jobs run on **Solid Queue** (database-backed) by default — no Redis
required. In development they execute in-process; to run a dedicated worker,
start `bin/jobs` in a separate terminal. Sidekiq + Redis remain supported as an
optional alternative.

### hdf-cli (HDF ↔ OSCAL translation bridge)

The translation endpoints shell out to the MITRE **hdf-libs** CLI. The Docker
image bakes it in, so this is only needed for local development against the
bridge — everything else runs without it.

```bash
sudo bin/install-hdf.sh          # installs the pinned version to /usr/local/bin
hdf version                      # confirm
```

`bin/install-hdf.sh` is the single source of truth for provisioning, shared by
the `Dockerfile` and CI. It downloads the release tarball, **verifies SHA-256
against the release `checksums.txt`**, and refuses to install on mismatch. It
defaults to the version SPARC pins (`HdfRunner::PINNED_VERSION`); override with
`HDF_LIBS_VERSION=x.y.z` to test another build, or `HDF_INSTALL_DIR=...` to
install somewhere other than `/usr/local/bin` (no `sudo` needed for a writable
directory):

```bash
HDF_LIBS_VERSION=3.4.1 HDF_INSTALL_DIR="$PWD/tmp/hdfbin" bin/install-hdf.sh
```

> **If `hdf version` still reports the old version after installing**, another
> copy is winning on `PATH`. A previous `go install` of hdf-libs leaves a binary
> in `$GOBIN` (usually `~/go/bin`), which commonly precedes `/usr/local/bin`.
> The installer now detects this and prints the fix. Check with `which hdf`, then
> either install over the copy that wins
> (`HDF_INSTALL_DIR="$(dirname "$(command -v hdf)")" bin/install-hdf.sh`) or
> remove it (`rm "$(command -v hdf)" && hash -r`).

SPARC only asserts the version when you ask it to: set
`SPARC_HDF_ALLOWED_VERSIONS` to refuse translations on an uncertified build.
Unset (default), it accepts whatever binary is present.

---

## Authentication Setup

Authentication is **opt-in** — all routes are public by default until you enable
an auth method.

### 1. Enable local login

Copy `.env.example` to `.env` and set:

```bash
SPARC_ENABLE_LOCAL_LOGIN=true
SPARC_ENABLE_USER_REGISTRATION=true
```

### 2. Seed the admin account

```bash
bin/rails db:seed
```

The seed task creates an admin account and prints the credentials to the console.
The admin must change their password on first login.

> **Lost your admin password?** Run `bin/rails sparc:bootstrap_admin` to
>regenerate credentials.

### 3. (Optional) Enable SSO

Add GitHub, GitLab, or Okta credentials to your `.env` — see [Authentication & Authorization](docs/AUTHENTICATION.md)
for full setup instructions.

**Important:** After any `.env` change, restart the Rails server. dotenv loads
environment variables at boot time only.

---

## Running Tests

```bash
bundle exec rspec        # Full test suite
bundle exec rubocop      # Linting
bundle exec brakeman     # Security scan
```

### Deployed & contract suites (optional)

Two language-agnostic suites run against a **live SPARC instance** (local or
deployed), outside the RSpec pyramid. Both are managed with [uv](https://docs.astral.sh/uv/)
and read config from a gitignored `.env` (copy the committed `.env.example`
template in each directory and fill in service-account tokens):

```bash
# API contract suite — every /api/v1 endpoint (~1–3 min)
cd tests/api      && cp .env.example .env   # then edit tokens
uv run pytest -q

# Playwright UI smoke — real-browser walks of the deployed UI (~1–4 min)
cd tests/ui-smoke && cp .env.example .env   # then edit tokens
uv run playwright install chromium          # first run only
uv run pytest -q
```

Generate tokens via **Admin → Service Accounts → New**. Some tests **skip**
when the target instance has no sample document of a given type to exercise, or
when an accessibility baseline hasn't been captured — skips are expected, not
failures. See [`tests/api/README.md`](tests/api/README.md) and
[`tests/ui-smoke/README.md`](tests/ui-smoke/README.md) for full details.
