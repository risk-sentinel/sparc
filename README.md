# SSP and TPR Manager

![Landing Page](docs/landing_page.png)

## Why Use the SSP-TPR-Manager App?

Managing **System Security Plans (SSP)** and **Test Plans & Results (TPR)** documents is often painful when everything lives in large, versioned Excel spreadsheets. The SSP-TPR-Manager app solves exactly that problem by turning complex, hard-to-coordinate spreadsheets into structured, web-accessible, collaborative data.

### Key Benefits

- **Transforms spreadsheets into usable information**  
  Instead of scrolling through massive Excel files, the app automatically parses SSP and TPR spreadsheets and organizes controls, fields, implementation status, test results, remediation plans, etc. into a clean, searchable web interface.

- **Enables real collaboration & coordination**  
  Security teams, system owners, assessors, and auditors can view and edit the same live data at the same time — no more emailing updated versions or wondering who has the “latest” spreadsheet.

- **Makes assessor coordination dramatically easier**  
  Large TPR datasets (hundreds or thousands of controls with test dates, results, findings, remediation plans) become filterable, sortable, and commentable. Assessors can quickly find open findings, overdue tests, or controls needing attention.

- **Supports meaningful responses & tracking**  
  Editable fields (responsible roles, implementation status, test results, remediation plans, etc.) are clearly marked. Changes are persisted in the database — teams can track progress, assign ownership, and generate exportable JSON summaries for reporting or compliance packages.

- **Reduces version chaos and errors**  
  No more “SSP v12_final_reallyfinal.xlsx” naming nightmares. One source of truth with status tracking (pending → processing → completed/failed).

- **Designed for real-world FedRAMP / RMF workflows**  
  Built specifically to handle the structure and fields common in SSP and TPR documents — responsible roles, implementation guidance, test status, tester names, findings, remediation plans, etc.

### Who Benefits Most?

- **Security / compliance teams** — easier to maintain and update the SSP  
- **Assessors / 3PAOs** — faster review of test results and remediation evidence  
- **System owners / ISSOs** — clear visibility into control status and gaps  
- **Program managers** — better reporting and coordination across large control sets

### In Short

The app takes the **painful, error-prone spreadsheet reality** of SSP/TPR management and replaces it with a **coordinated, web-based, real-time source of truth** that actually helps teams document, assess, respond, and prove compliance.

If you're tired of version conflicts, lost changes, or spending hours hunting for the right test result in a 10,000-row spreadsheet — this app is built to make that part of your job noticeably less miserable.

SSP and TPR Manager comprehensive Rails application provides:

- ✅ SSP Management - Upload, convert, edit, and export SSP documents
- ✅ TPR Management - Upload, convert, and manage TPR documents
- ✅ Excel to JSON Conversion - Automatic parsing of Excel files
- ✅ Web-based Editor - User-friendly interface for editing controls
- ✅ API Endpoints - RESTful API for programmatic access
- ✅ Background Processing - Async job processing for large files
- ✅ Database Persistence - Store and version control documents
- ✅ Export Capabilities - Download as JSON
- ✅ Extensible Architecture - Easy to add update_tpr functionality

The application is production-ready with proper error handling, validation, testing support, and Docker containerization options!

* Ruby version 3.4.4
* Rails version 8.1.2

## Running The App

### Local Development and testing

#### 1. Clone the Repo

```bash
git clone https://github.com/yourusername/ssp_tpr_manager.git && \
cd ssp_tpr_manager
```

#### 2. (Optionally) Create a `.env` file

```bash
touch .env
```

Update the `.env`

```bash
# Change web port if 3000 is already in use
WEB_PORT=3001

# Optional: custom Postgres password
POSTGRES_PASSWORD=your-secure-password
```

#### 3. Create the database and run migrations

```bash
rails db:create
rails db:migrate
```

#### 4. Install active storage

```bash
rails active_storage:install
rails db:migrate
```

#### 5. Start Redis for Sidekiq

```bash
redis-server
```

#### 6. Start Sidekiq (in a separate terminal)

```bash
bundle exec sidekiq
```

#### 7. Start the Rails server:

```bash
rails server
```

### Docker

```bash
docker comopse up --build
```

* --build ensures images are freshly built (only needed the first time or after changing code/Dockerfile/Gemfile)
* First run may take 3–10 minutes (downloads Ruby/Postgres/Redis images, installs gems, precompiles assets, runs migrations)
* Later starts are usually < 20 seconds

You should eventually see output like:

```bash
web-1     | Waiting for PostgreSQL...
web-1     | PostgreSQL is ready!
web-1     | Preparing database...
web-1     | => Booting Puma...
web-1     | * Listening on http://0.0.0.0:3000
```

## Access the application

* [Home](http://localhost:3000)
* [SSP Documents](http://localhost:3000/ssp_documents)
* [TPR Documents](http://localhost:3000/tpr_documents)
* [SSP Editor](http://localhost:3000/ssp_documents/[id]/editor)

## Troubleshooting tips

* Port 3000 already in use
    * Change the port in docker-compose.yaml (under web service: ports: - "3001:3000") or stop the conflicting process.
* Database connection refused / timeout
    * Wait a bit longer — first startup can be slow. Check docker compose logs db to confirm Postgres is running.
* Migrations seem stuck or fail
    * The entrypoint automatically runs db:prepare on web startup. If needed, run manually:
    * `docker compose exec web bin/rails db:migrate`
* Sidekiq not starting / no jobs processing
    * Check logs: `docker compose logs sidekiq`
It should show "Sidekiq 8.1.1 ... connecting to Redis"
* Still stuck?
    * Run docker compose logs and look for errors. Feel free to open an issue on GitHub with the output.