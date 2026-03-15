# Docker Deployment

## Development

```bash
docker compose up --build
```

- `--build` is only needed the first time or after changing `Dockerfile` / `Gemfile`
- First run may take 3-10 minutes (downloads images, installs gems, runs migrations)
- Subsequent starts are typically under 20 seconds

Services started:

- **web** — Rails app on port 3000
- **db** — PostgreSQL 15 on port 5433 (avoids local conflicts)
- **redis** — Redis 7 on port 6380
- **sidekiq** — Background job processor

Once the app is running, open
**<http://localhost:3000>** in your browser.

### Development HTTPS

To enable HTTPS in Docker Compose:

1. Run `bin/setup-ssl` on your host machine
2. Add `SSL_DEV=true` to your `.env` file (or uncomment in
   `docker-compose.yaml`)
3. Start normally: `docker compose up`
4. Open **<https://localhost:3443>**

See `docs/development-https.md` for full details.

### Seed NIST Catalogs

```bash
docker compose exec web bin/rails db:seed
```

<!-- markdownlint-disable MD013 -->

This seeds NIST SP 800-53 Rev 4 (18 families, 256 controls) and Rev 5 (20 families, 323 controls), 9 RMF roles, and bootstraps an admin account (if local login is enabled).

<!-- markdownlint-enable MD013 -->

---

## Production

<!-- markdownlint-disable MD013 -->

A production Docker Compose configuration is available at `docker-compose-prod.yaml`. Deployment is configured for [Kamal](https://kamal-deploy.org/) via `config/deploy.yml`.

<!-- markdownlint-enable MD013 -->

```bash
docker compose -f docker-compose-prod.yaml up --build -d
```

---

## Common Commands

```bash
# View logs
docker compose logs -f web

# Run migrations
docker compose exec web bin/rails db:migrate

# Seed NIST catalogs and roles
docker compose exec web bin/rails db:seed

# Rails console
docker compose exec web bin/rails console

# Stop all services
docker compose down
```
