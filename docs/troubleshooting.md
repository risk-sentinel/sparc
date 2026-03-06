# Troubleshooting

Common issues and their solutions when running SPARC.

---

## Docker Issues

**Port 3000 already in use** — Change the port in `docker-compose.yaml` under the `web` service (`ports: - "3001:3000"`) or stop the conflicting process.

**Database connection refused** — Wait a bit longer on first startup. Check `docker compose logs db` to confirm Postgres is running.

**Migrations fail** — The entrypoint automatically runs `db:prepare` on web startup. If needed, run manually: `docker compose exec web bin/rails db:migrate`

**Sidekiq not processing jobs** — Check logs: `docker compose logs sidekiq`. Ensure Redis is running.

---

## File Upload Issues

**SSP upload stuck on "pending"** — Ensure Sidekiq is running (`docker compose logs sidekiq`). SSP files are processed asynchronously via a background job.

**Unsupported file type error** — SSP and SAR documents require `.xlsx` or `.xls` Excel files. Profiles accept `.xml` (XCCDF) or `.json` (InSpec/STIG Viewer).

**Large file timeout** — Files are persisted to disk before background processing begins, so timeouts should not occur. If the upload itself times out, check your reverse proxy configuration for request size limits.

---

## Local Development Issues

**`bundle install` fails** — Ensure PostgreSQL development headers are installed (`libpq-dev` on Debian/Ubuntu, `postgresql` via Homebrew on macOS).

**Redis connection refused** — Start Redis locally (`redis-server`) or via Docker before running Sidekiq.

**Missing `rails_helper.rb`** — The project uses RSpec. Run tests with `bundle exec rspec`, not `rails test`.

---

## Production Issues

**Assets not loading** — Ensure `RAILS_SERVE_STATIC_FILES=true` is set, or configure a reverse proxy (Nginx, ALB) to serve `/public/assets`.

**SSL redirect loop** — If behind a load balancer that terminates SSL, set `FORCE_SSL=false` since Rails' `assume_ssl` handles the HTTPS headers. The load balancer should set `X-Forwarded-Proto: https`.

**Secret key errors** — Generate a production secret with `bin/rails secret` and set it as `SECRET_KEY_BASE`.

---

## Still Stuck?

Run `docker compose logs` and look for errors. Feel free to [open an issue](https://github.com/Rebel-Raiders/sparc/issues) with the output.
