source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.3"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.1"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem "importmap-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

gem "csv", "~> 3.3"              # CSV file parsing
gem "roo", "~> 3.0.0"              # .xlsx file parsing (MIT)
# NOTE (#479): `roo-xls` was removed because its transitive `spreadsheet`
# gem is GPL-3.0-only and incompatible with SPARC's Apache-2.0 license
# at runtime. Legacy .xls (Excel 97-2003 binary) support was dropped;
# .xlsx parsing via `roo` is preserved.
gem "rubyzip", "~> 3.4.0"          # ZIP file handling
gem "activerecord-import"           # Bulk imports
gem "caxlsx", "~> 4.5"             # Excel .xlsx generation
gem "pagy", "~> 43.5"              # Pagination
gem "sidekiq"                       # Background jobs
gem "redis", "~> 5.0"              # For Sidekiq
gem "aws-sdk-s3"                    # File storage
gem "aws-sdk-secretsmanager", "~> 1.133"  # Secrets Manager (ECS deployments)
gem "aws-sdk-rds", "~> 1.316"           # IAM DB auth token generation
gem "json_schemer", "~> 2.3"         # JSON Schema validation (OSCAL)
gem "resolv", ">= 0.7.0"            # CVE-2025-24294 ReDoS fix (overrides Ruby 3.4.4 bundled 0.6.0)
# #620 — pin patched versions of Ruby default gems so Bundler loads them instead
# of the vulnerable versions shipped in ruby:3.4.4-slim (same pattern as resolv).
gem "zlib", ">= 3.2.3"             # CVE-2026-27820 (overrides bundled 3.2.1)
gem "net-imap", ">= 0.6.4"         # CVE-2026-42257/42258 (CRITICAL) + 42245/42246 (overrides bundled 0.5.8)
gem "erb", ">= 6.0.4"             # CVE-2026-41316 (overrides bundled 4.0.4)
gem "oauth2", ">= 2.0.22"          # GHSA-pp92-crg2-gfv9 (bumps transitive 2.0.18)
gem "dotenv-rails", require: false, groups: [ :development, :test ]

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.22"

# ── Security ────────────────────────────────────────────────────────────────
gem "rack-attack", "~> 6.7"                    # Rate limiting + throttling (#513)

# ── Authentication ──────────────────────────────────────────────────────────
gem "omniauth", "~> 2.1"                       # OAuth/OIDC foundation
gem "omniauth-rails_csrf_protection", "~> 2.0" # CSRF protection for OmniAuth POST
gem "omniauth-github", "~> 2.0"                # GitHub OAuth
gem "omniauth-gitlab", "~> 4.0"                # GitLab OAuth
gem "omniauth_openid_connect", "~> 0.8"        # Generic OIDC (Okta, Keycloak, Entra ID)
gem "net-ldap", "~> 0.19"                      # LDAP authentication
gem "jwt", "~> 3.2"                            # JWT decoding for OIDC API token validation

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ mswin mingw jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
gem "solid_queue"
gem "solid_cable"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# #639 — thruster removed. It was a Rails 8 default (`require: false`) and was
# never required or executed (CMD runs Puma directly; in prod TLS/HTTP2/gzip/
# static are handled by the ALB/proxy). Its vendored static Go binary was baked
# into the image and only added CVE surface (8 CRITICALs, #612) with no runtime
# use, so it's dropped. Re-add if an in-container HTTP/2 + X-Sendfile proxy is
# ever needed without an external proxy in front.

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 2.0"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri mswin mingw ], require: false

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
end

group :development, :test do
  gem "rspec-rails", "~> 8.0.4"
  gem "factory_bot_rails"
  gem "faker"
  gem "bundler-audit", require: false
  # NOTE (#463): cyclonedx-ruby was removed — v1.1.0 only emits XML despite
  # the .cdx.json extension we used in CI. Replaced with @cyclonedx/cdxgen
  # in .github/workflows/security.yml (emits valid CycloneDX JSON).
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  # Layer 3 accessibility (#599) — axe-core matchers for system specs
  gem "axe-core-rspec"
  gem "shoulda-matchers", "~> 8.0"
  gem "simplecov", require: false
end
