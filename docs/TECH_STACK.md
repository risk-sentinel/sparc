# Technology Stack

## Core Framework

| Component | Version | Purpose |
|-----------|---------|---------|
| Ruby | 3.4.4 | Language runtime |
| Rails | 8.1.2 | Web framework |
| PostgreSQL | 15 | Primary database |
| Sidekiq | 8.1.1 | Background job processing |
| Redis | 7+ | Job queue backend |
| Puma | 7.2.0 | Application server |

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
