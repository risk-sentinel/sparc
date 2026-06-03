# Technology Stack

## Core Framework

| Component | Version | Purpose |
|-----------|---------|---------|
| Ruby | 3.4.4 | Language runtime |
| Rails | 8.1.3 | Web framework |
| PostgreSQL | 15 | Primary database |
| Puma | 8.0.2 | Application server |
| Solid Queue | 1.4.0 | Background jobs — DB-backed, **default in production** |
| Solid Cache | 1.0.10 | Caching — DB-backed |
| Solid Cable | 3.0.12 | Action Cable backend — DB-backed |
| Sidekiq | 8.1.6 | Background jobs — optional alternative to Solid Queue |
| Redis | 7+ | Backend for Sidekiq (optional) |

> Versions current as of **v1.8.6**. `Gemfile.lock` is the authoritative source
> of truth for exact gem versions; this table tracks the load-bearing ones for
> orientation. Dependency bumps land via Dependabot (grouped patch/minor PRs).

## Frontend

| Component | Purpose |
|-----------|---------|
| Hotwire (Turbo + Stimulus) | Interactive UI without a JavaScript SPA |
| Propshaft | Asset pipeline |
| Importmap | JavaScript module loading (no Node.js build step) |

## Authentication

| Component | Purpose |
|-----------|---------|
| bcrypt | Local password hashing (has_secure_password) |
| OmniAuth | OAuth2 / OIDC framework (GitHub, GitLab, Okta) |
| net-ldap | LDAP bind-and-search authentication |

## Testing & Quality

| Tool | Purpose |
|------|---------|
| RSpec | Test framework |
| FactoryBot + Faker | Test data generation |
| RuboCop (rails-omakase) | Code style linting |
| Brakeman | Static security analysis |
| Capybara + Selenium | System/integration tests |

## DevOps & Deployment

| Tool | Purpose |
|------|---------|
| Docker + Docker Compose | Containerized development and deployment |
| Kamal | Docker-based production deployment |
| GitHub Actions | CI/CD pipeline (lint, security scan, tests) |
| Dependabot | Automated dependency updates |
| Active Storage | File uploads (local dev / S3 production) |
