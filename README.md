# SPARC — Systemized Policy and Regulatory Controls

![Landing Page](docs/landing_page.png)

**SPARC** is a control catalog management and compliance documentation platform purpose-built to modernize how organizations manage, track, and implement NIST 800-53 (and related) security and privacy controls. SPARC transforms static spreadsheets and siloed documents into a **coordinated, web-based, real-time source of truth** — empowering security teams, assessors, system owners, and program managers to document, assess, respond to, and prove compliance.

---

## What is SPARC?

**SPARC (Systemized Policy and Regulatory Controls)** centralizes, normalizes, and operationalizes compliance frameworks including:

- NIST SP 800-53 Rev 4 and Rev 5 (pre-loaded)
- FedRAMP Low / Moderate / High baselines
- Custom internal control overlays

SPARC supports the full lifecycle of compliance documentation — from catalog management and SSP authoring to test plan execution and results tracking — while producing structured, exportable data for reporting and audit packages.

---

## Why SPARC?

Managing **System Security Plans (SSP)** and **Test Plans & Results (TPR)** is painful when everything lives in large, versioned Excel spreadsheets. SPARC solves that by replacing spreadsheets with a structured, web-accessible, collaborative platform.

| Benefit | Description |
|---------|-------------|
| Eliminate version chaos | No more `SSP_v12_final_REALLYFINAL.xlsx` — one source of truth with status tracking |
| Enable collaboration | Security teams, assessors, and system owners view and edit the same live data simultaneously |
| Accelerate assessor coordination | Hundreds of controls with test results, findings, and remediation plans become filterable and searchable |
| Visual compliance coverage | Interactive heat maps show implementation and test status by NIST control family at a glance |
| Structured data export | Export SSPs and TPRs as JSON for reporting, compliance packages, or downstream tooling |
| Audit readiness | Track progress, assign ownership, and generate exportable artifacts for ATO packages |

### Who Benefits Most

- **Security / compliance teams** — maintain and update SSPs without spreadsheet coordination overhead
- **Assessors / 3PAOs** — quickly find open findings, overdue tests, and controls needing attention
- **System owners / ISSOs** — clear visibility into control implementation status and gaps by family
- **Program managers** — better reporting and coordination across large control sets

---

## Features

- **Control Catalog Management** — Browse, create, and manage NIST and custom control catalogs with family and control-level CRUD. NIST SP 800-53 Rev 4 (256 controls) and Rev 5 (323 controls) are pre-loaded.
- **SSP Management** — Upload Excel-based SSPs, automatically parse controls and fields, edit implementation status, and export to JSON.
- **TPR Management** — Upload and manage Test Plan Reports with color-coded test status indicators.
- **Interactive Heat Maps** — Collapsible status heat maps on SSP and TPR pages display implementation/test status by NIST control family. Click any cell to filter the control list below it.
- **Inline Field Editing** — Edit designated fields (responsible roles, implementation status, test results, remediation plans) directly in the browser; read-only fields are enforced.
- **Excel to JSON Conversion** — Automatic parsing of Excel files via background job (SSP) or synchronous processing (TPR).
- **JSON Export** — Download any document as a formatted JSON file.
- **RESTful API** — Programmatic access to convert, update, and export documents via `/api/v1/` endpoints.
- **Background Processing** — Async job processing for large SSP files via Sidekiq.

---

## Stack

| Component | Version |
|-----------|---------|
| Ruby | 3.4.4 |
| Rails | 8.1.2 |
| Database | PostgreSQL 15 |
| Background Jobs | Sidekiq + Redis |
| File Storage | Active Storage (local dev / S3 prod) |
| Deployment | Docker / Kamal |

---

## Running SPARC

### Docker (Recommended)

```bash
git clone https://github.com/yourusername/sparc.git
cd sparc
docker compose up --build
```

- `--build` is only needed the first time or after changing `Dockerfile` / `Gemfile`
- First run may take 3–10 minutes (downloads images, installs gems, precompiles assets, runs migrations)
- Subsequent starts are typically under 20 seconds

You should see:

```
web-1  | Waiting for PostgreSQL...
web-1  | PostgreSQL is ready!
web-1  | Preparing database...
web-1  | => Booting Puma...
web-1  | * Listening on http://0.0.0.0:3000
```

After the app is up, load the catalog seed data:

```bash
docker compose exec web bin/rails db:seed
```

This seeds NIST SP 800-53 Rev 4 (18 families, 256 controls) and Rev 5 (20 families, 323 controls).

### Local Development

#### 1. Clone and install

```bash
git clone https://github.com/yourusername/sparc.git
cd sparc
bundle install
```

#### 2. (Optional) Create a `.env` file

```bash
touch .env
```

```bash
# Change web port if 3000 is already in use
WEB_PORT=3001

# Optional: custom Postgres password
POSTGRES_PASSWORD=your-secure-password
```

#### 3. Set up the database

```bash
bin/rails db:create
bin/rails db:migrate
bin/rails active_storage:install
bin/rails db:migrate
bin/rails db:seed
```

#### 4. Start background services

```bash
# Terminal 1 — Redis
redis-server

# Terminal 2 — Sidekiq
bundle exec sidekiq
```

#### 5. Start the server

```bash
bin/rails server
```

---

## Access the Application

| Page | URL |
|------|-----|
| Home / Dashboard | http://localhost:3000 |
| SSP Documents | http://localhost:3000/ssp_documents |
| TPR Documents | http://localhost:3000/tpr_documents |
| Control Catalogs | http://localhost:3000/control_catalogs |
| SSP Editor | http://localhost:3000/ssp_documents/[id]/editor |

---

## Importing Existing Catalogs

SPARC's catalog importer accepts Excel files with the following column structure.

### Catalog File Columns

| Column Name | Description | Example |
|-------------|-------------|---------|
| `family` | NIST or other control family | `ACCESS CONTROL` |
| `control_id` | Control identifier | `AC-1` |
| `title` | Control title | `ACCESS CONTROL POLICY AND PROCEDURES` |
| `priority` | Implementation priority | `P1` |
| `overlay` | Applicable baselines/overlays | `LOW, MODERATE, HIGH` |
| `language` | Base control language | `The organization:` |
| `related_controls` | Related control identifiers | `PM-9` |
| `supplemental_guidance` | Supplemental guidance text | `This control addresses...` |
| `implementation_guidance` | Guidance for satisfying the control | *(to be added)* |
| `nist_references` | Supporting NIST references | `NIST-800-53v4` |
| `internal_references` | Applicable internal policies | `PR.AC-001` |
| `check` | How the control is validated | `Examine supporting policy documents` |
| `fix` | Remediation for a failing control | `Ensure that policy establishes...` |

> **Note:** Column order does not matter. Null / NaN values are filled with `"Not Available"` at creation.

### Part A (Assessment Objectives) Columns

| Column Name | Description | Example |
|-------------|-------------|---------|
| `family` | NIST or other control family | `ACCESS CONTROL` |
| `control_id` | Control identifier | `AC-1` |
| `title` | Control title | `ACCESS CONTROL POLICY AND PROCEDURES` |
| `decision` | Pass/fail determination criteria | `Determine if the organization: ...` |
| `examine` | What needs to be reviewed/tested | `Access control policy and procedures...` |
| `test` | Test to be performed | `Organizational processes for account management...` |
| `interview` | Interview guidance | `Organizational personnel with access control responsibilities...` |

---

## Troubleshooting

**Port 3000 already in use**
Change the port in `docker-compose.yaml` under the `web` service (`ports: - "3001:3000"`) or stop the conflicting process.

**Database connection refused / timeout**
Wait a bit longer — first startup can be slow. Check `docker compose logs db` to confirm Postgres is running.

**Migrations seem stuck or fail**
The entrypoint automatically runs `db:prepare` on web startup. If needed, run manually:
```bash
docker compose exec web bin/rails db:migrate
```

**Sidekiq not starting / no jobs processing**
Check logs: `docker compose logs sidekiq`. You should see `Sidekiq 8.x ... connecting to Redis`.

**Still stuck?**
Run `docker compose logs` and look for errors. Feel free to open an issue on GitHub with the output.

---

## Related Projects

- [MITRE OSCAL](https://pages.nist.gov/OSCAL/) — Open Security Controls Assessment Language
- [Open Policy Agent (OPA)](https://www.openpolicyagent.org/) — Policy-as-code enforcement
- [Terraform Compliance](https://terraform-compliance.com/) — Infrastructure compliance testing

---

## Contributing

Contributions are welcome. Please read the contributing guide and code of conduct before submitting a pull request.
