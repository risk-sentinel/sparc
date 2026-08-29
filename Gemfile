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
gem "rubyzip", "~> 3.5.0"          # ZIP file handling
gem "activerecord-import"           # Bulk imports
gem "caxlsx", "~> 4.5"             # Excel .xlsx generation
gem "pagy", "~> 43.6"              # Pagination
gem "sidekiq"                       # Background jobs
gem "redis", "~> 6.0"              # For Sidekiq
gem "aws-sdk-s3"                    # File storage
gem "aws-sdk-secretsmanager", "~> 1.134"  # Secrets Manager (ECS deployments)
gem "aws-sdk-rds", "~> 1.319"           # IAM DB auth token generation
gem "json_schemer", "~> 2.3"         # JSON Schema validation (OSCAL)
# #620 / #1065 — pin patched versions of Ruby DEFAULT gems so Bundler loads them
# instead of the copy Ruby ships. Two independent layers, and both are wanted:
#
#   * these pins fix the code that is LOADED (Bundler resolves from /usr/local/bundle)
#   * the RUBY_VERSION in the Dockerfile fixes the copy that sits ON DISK, which is
#     what a scanner reports — it reads gemspecs, not what Bundler loaded
#
# Ruby 3.4.10 (up from 3.4.4, #1065) makes four of the five on-disk copies patched
# at source, which is why the image's CRITICAL/HIGH residual is 0 rather than
# dispositioned away. Versions below are what 3.4.10 ships:
gem "resolv", ">= 0.7.2"            # CVE-2025-24294 ReDoS + CVE-2026-80212/80213 — 3.4.10 ships
                                    # 0.7.1 on disk, which the 2026-08-29 advisories made vulnerable
gem "zlib", ">= 3.2.3"             # CVE-2026-27820        — 3.4.10 ships 3.2.3, patched
gem "erb", ">= 6.0.4"             # CVE-2026-41316        — 3.4.10 ships 4.0.4.1, the upstream backport
gem "uri", ">= 1.1.1"              # CVE-2025-61594        — 3.4.10 ships 1.0.4, patched (advisory: >= 1.0.4)
# json is the ONE default gem Ruby 3.4.10 still ships vulnerable (2.9.1; fixed
# upstream in 2.19.9). It was invisible to #1065's original survey because that
# was built from Trivy's CRITICAL/HIGH output and this is CVSS 3.7 LOW. The pin
# matters on its own: json is purely TRANSITIVE here, and its binding constraints
# (`~> 2.3`, `>= 2.16.0`) admit 2.16.0–2.19.8, every one of them vulnerable — so
# a resolver change could legally walk back into the window. This forbids that.
gem "json", ">= 2.19.9"            # CVE-2026-54696        — 3.4.10 ships 2.9.1, STILL VULNERABLE on disk
gem "net-imap", ">= 0.6.4"         # CVE-2026-42257/42258 (CRITICAL) + 42245/42246 (overrides bundled 0.5.8)
gem "oauth2", ">= 2.0.22"          # GHSA-pp92-crg2-gfv9 (bumps transitive 2.0.18)
gem "websocket-driver", ">= 0.8.2"  # CVE-2026-54463/54464/54465 + GHSA-2x63-gw47-w4mm DoS (bumps transitive 0.8.0)
gem "crass", ">= 1.0.7"            # GHSA-6jxj/6wmf/8vfg/wwpr ReDoS/stack-overflow (bumps transitive 1.0.6)
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
gem "webauthn", "~> 3.1"                       # FIDO2/WebAuthn passwordless + 2FA (#779)
# Pin the openssl *gem* (the thin Ruby binding, NOT the OpenSSL C library) to the
# 3.x line — which is exactly what the UBI9 prod image already ships (Ruby 3.4.4's
# default) and what production's OpenSSL 3.x library expects. This is NOT a
# downgrade: prod's crypto/TLS engine is the OpenSSL 3.x *library* regardless of
# this pin. Without it, webauthn's loose `openssl > 2.0` lets bundler grab the new
# 4.x gem, whose native ext drops OpenSSL 1.1.1 support and segfaults on dev boxes
# whose Ruby links 1.1.1 — so the pin also keeps dev/prod at the same gem. `~> 3.3`
# still admits all 3.x security patches. (#779)
gem "openssl", "~> 4.0"

# Bundle the IANA tz database (pure Ruby) so TZInfo needs no system zoneinfo.
# Not just Windows/JRuby: minimal Linux base images ship no usable
# /usr/share/zoneinfo tab files either (e.g. UBI9 minimal, #742), so make it
# unconditional. Harmless on Debian — TZInfo just prefers the gem data source.
gem "tzinfo-data"

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
# Reviewed 2026-08-23 (Bundle X). The `~> 1.5.0` pin carried a standing note to
# review 1.6.0 separately; this is that review. 1.6.0's headline is an OPT-IN
# fiber execution mode — it needs `fibers:` in the worker config AND
# `config.active_support.isolation_level = :fiber`, and SPARC sets neither, so
# the new path is unreachable here. The rest is bug fixes. Widened to `~> 1.7`
# rather than `~> 1.7.0` so patch and future minor fixes arrive without another
# pin edit — the three-digit form is exactly what let this pin go stale.
gem "solid_queue", "~> 1.7"
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

# Active Storage variants: NOT USED, and the gem is deliberately absent.
#
# SPARC attaches files (evidence, document uploads, the admin avatar) but never
# derives images from them — there is no `.variant`, `.representation` or
# `.preview` call anywhere in app/, and the avatar renders the original blob via
# `image_tag user.avatar`. The gem was vestigial.
#
# Removing it is what makes Rails 8.1.3.1 bootable. The CVE-2026-66066 patch
# hardens Active Storage by disabling libvips' untrusted image loaders AT BOOT,
# which reaches for `ImageProcessing::Vips` -> `ruby-vips` -> libvips. Those were
# never in the Gemfile or the image, so with `image_processing` present the app
# aborts in config/environment.rb before serving anything — in every
# environment, not only under CI's eager loading.
#
# The alternative was adding ruby-vips plus libvips >= 8.13 to the UBI9 image:
# a native dependency, a larger CVE surface, and a hard version floor, all to
# support a feature nothing calls. If image derivatives are ever wanted, add
# `image_processing` AND `ruby-vips` together, ensure libvips >= 8.13 is in the
# image, and review `config.active_storage.variable_content_types` — the CVE
# advisory notes BMP/ICO/PSD handling breaks under the hardened loaders.

# #784 — render the in-app User Guides (Help Center) from the wiki Markdown
# sources at request time. kramdown + its GFM parser are PURE RUBY (no native
# extension), so they add zero build risk to the UBI9 image, unlike C/Rust
# markdown gems. Nokogiri (already present transitively via Rails) does the
# post-render pass (image/link rewrite, Mermaid fences, Bootstrap tables).
gem "kramdown", "~> 2.5"
gem "kramdown-parser-gfm", "~> 1.1"

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
