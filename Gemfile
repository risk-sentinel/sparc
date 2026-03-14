source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.2"
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
gem "roo", "~> 3.0.0"              # Excel file parsing
gem "roo-xls", "~> 2.0.0"          # .xls support
gem "rubyzip", "~> 3.2.2"          # ZIP file handling
gem "activerecord-import"           # Bulk imports
gem "caxlsx", "~> 4.1"             # Excel .xlsx generation
gem "pagy", "~> 43.3"              # Pagination
gem "sidekiq"                       # Background jobs
gem "redis", "~> 5.0"              # For Sidekiq
gem "aws-sdk-s3"                    # File storage
gem "json_schemer", "~> 2.3"         # JSON Schema validation (OSCAL)
gem "dotenv-rails", require: false, groups: [ :development, :test ]

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.7"

# ── Authentication ──────────────────────────────────────────────────────────
gem "omniauth", "~> 2.1"                       # OAuth/OIDC foundation
gem "omniauth-rails_csrf_protection", "~> 2.0" # CSRF protection for OmniAuth POST
gem "omniauth-github", "~> 2.0"                # GitHub OAuth
gem "omniauth-gitlab", "~> 4.0"                # GitLab OAuth
gem "omniauth_openid_connect", "~> 0.8"        # Generic OIDC (Okta, Keycloak, Entra ID)
gem "net-ldap", "~> 0.19"                      # LDAP authentication

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

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
# gem "image_processing", "~> 1.2"

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
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  gem "shoulda-matchers", "~> 7.0"
  gem "simplecov", require: false
end
