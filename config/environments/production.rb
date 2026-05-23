require "active_support/core_ext/integer/time"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.
  # See docs/ENVIRONMENT_VARIABLES.md for the full SPARC configuration reference.
  #
  # NIST 800-53 Controls:
  #   SC-8  Transmission Confidentiality (FORCE_SSL + HSTS preload)
  #   SC-13 Cryptographic Protection (TLS enforcement)
  #   SC-28 Protection of Information at Rest (S3 SSE, SolidCache)
  # See: docs/compliance/nist-sp800-53-rev5-mapping.md

  # Code is not reloaded between requests.
  config.enable_reloading = false

  # Eager load code on boot for better performance and memory savings (ignored by Rake tasks).
  config.eager_load = true

  # Full error reports are disabled.
  config.consider_all_requests_local = false

  # Turn on fragment caching in view templates.
  config.action_controller.perform_caching = true

  # Cache assets for far-future expiry since they are all digest stamped.
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.asset_host = "http://assets.example.com"

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :local

  # #515: serve user-uploaded blobs from a cookieless subdomain.
  # SPARC_USERDATA_HOST override OR "userdata.<host>" derived from
  # SPARC_APP_URL. Every rails_blob_url / url_for(blob) call now emits
  # URLs on the userdata.* origin. Browser does not send the SPARC
  # session cookie to that origin (host-only cookie — see
  # config/initializers/session_store.rb). Pairs with sparc-iac DNS/
  # ALB/cert.
  #
  # ENV read directly here (not via SparcConfig). Environment configs
  # load before Zeitwerk autoloads app/models, so a SparcConfig.* call
  # at the top of this file would raise NameError during
  # assets:precompile / Docker build. The SparcConfig accessors still
  # exist for app code; this duplication is intentional and minimal.
  userdata_host = ENV["SPARC_USERDATA_HOST"].presence
  app_url_env   = ENV["SPARC_APP_URL"].presence
  if userdata_host.nil? && app_url_env
    begin
      app_uri       = URI.parse(app_url_env)
      userdata_host = "userdata.#{app_uri.host}" if app_uri.host.present?
    rescue URI::InvalidURIError
      # leave userdata_host nil; ActiveStorage falls back to request host
    end
  end

  if userdata_host
    userdata_protocol = begin
      URI.parse(app_url_env || "https://x").scheme
    rescue URI::InvalidURIError
      "https"
    end
    config.active_storage.url_options = {
      host:     userdata_host,
      protocol: userdata_protocol
    }
  end

  # Assume all access to the app is happening through a SSL-terminating reverse proxy.
  config.assume_ssl = true

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # Configurable via FORCE_SSL env var (default: true in production).
  config.force_ssl = ENV.fetch("FORCE_SSL", "true") == "true"

  # HSTS: 1-year max-age with subdomains and preload per NIST SP 800-53 SC-8.
  # Skip http-to-https redirect for the /up health check endpoint so container
  # probes (ALB, Kubernetes) that hit HTTP internally still get a 200.
  config.ssl_options = {
    hsts: { expires: 1.year, subdomains: true, preload: true },
    redirect: { exclude: ->(request) { request.path == "/up" } }
  }

  # Log to STDOUT with the current request id as a default log tag.
  config.log_tags = [ :request_id ]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Configurable via SPARC_LOG_LEVEL (preferred) or RAILS_LOG_LEVEL (legacy fallback).
  config.log_level = ENV.fetch("SPARC_LOG_LEVEL", ENV.fetch("RAILS_LOG_LEVEL", "info"))

  # Prevent health checks from clogging up the logs.
  config.silence_healthcheck_path = "/up"

  # Don't log any deprecations.
  config.active_support.report_deprecations = false

  # Replace the default in-process memory cache store with a durable alternative.
  config.cache_store = :solid_cache_store

  # Replace the default in-process and non-durable queuing backend for Active Job.
  config.active_job.queue_adapter = :solid_queue
  config.solid_queue.connects_to = { database: { writing: :queue } }

  # ── Mailer Configuration ─────────────────────────────────────────────────
  # Set host from SPARC_APP_URL for links generated in mailer templates.
  mailer_host = ENV.fetch("SPARC_APP_URL", "https://example.com")
                   .gsub(%r{\Ahttps?://}, "")
                   .split(":").first
  config.action_mailer.default_url_options = { host: mailer_host }

  # SMTP delivery — enabled via SPARC_ENABLE_SMTP=true.
  # See docs/ENVIRONMENT_VARIABLES.md for all SPARC_SMTP_* variables.
  if ENV["SPARC_ENABLE_SMTP"] == "true"
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
      address: ENV.fetch("SPARC_SMTP_ADDRESS", "localhost"),
      port: ENV.fetch("SPARC_SMTP_PORT", "587").to_i,
      user_name: ENV.fetch("SPARC_SMTP_USERNAME", nil),
      password: ENV.fetch("SPARC_SMTP_PASSWORD", nil),
      authentication: ENV.fetch("SPARC_SMTP_AUTH", "plain").to_sym,
      enable_starttls_auto: ENV.fetch("SPARC_SMTP_STARTTLS_AUTO", "true") == "true"
    }
  end

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false

  # Only use :id for inspections in production.
  config.active_record.attributes_for_inspect = [ :id ]

  # Enable DNS rebinding protection and other `Host` header attacks.
  # config.hosts = [
  #   "example.com",     # Allow requests from example.com
  #   /.*\.example\.com/ # Allow requests from subdomains like `www.example.com`
  # ]
  #
  # Skip DNS rebinding protection for the default health check endpoint.
  # config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

  config.active_storage.service = :amazon
end
