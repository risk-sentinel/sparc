require_relative "boot"

require "rails/all"

# #785 — the JSON log formatter lives outside the Zeitwerk-managed lib/ tree
# (see the `logging` entry in the autoload ignore list below) and is wired up in
# the Application config block, before autoloading exists. Required here at the
# top of the file rather than inside that block. (sonar rubydre:S7816)
require_relative "../lib/logging/sparc_json_formatter"

# #785 Pass 2 — DbUrl derives all four databases from DATABASE_URL. Required here
# so the constant exists by the time config/database.yml renders (database.yml
# must stay raw-YAML-parseable, so it cannot `<% require %>` the helper itself).
require_relative "../lib/db_url/config"

# Skip dotenv in production/containers
if Rails.env.development? || Rails.env.test?
  begin
    require "dotenv/load"
  rescue LoadError
    # Silently skip if gem not present (e.g., in Docker prod build)
  end
end

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module SspTprManager
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # `logging` is ignored because config/application.rb requires the formatter
    # directly, before autoloading exists — letting Zeitwerk also manage it would
    # be a double definition.
    # `db_url` is ignored because config/database.yml requires it directly, before
    # autoloading exists (#785 Pass 2). `logging` for the same reason (the JSON
    # formatter). Letting Zeitwerk also manage either would be a double definition.
    config.autoload_lib(ignore: %w[assets tasks logging db_url])

    # ── Log destination and format (#785) ────────────────────────────────────
    # Applied here, in application.rb, so it covers EVERY environment. It used
    # to be a hardcoded STDOUT line in production.rb, which meant
    # SPARC_LOG_TO_STDOUT was read by nothing (verified: setting it to "false"
    # still logged to stdout) and any non-production container wrote to a file
    # inside the image, where `docker logs` and CloudWatch could never see it.
    #
    # Defaults to true in production; opt in elsewhere. Both variables remain
    # overrides — neither is required.
    log_to_stdout = ENV.fetch("SPARC_LOG_TO_STDOUT") { Rails.env.production?.to_s } == "true"
    structured    = ENV.fetch("SPARC_STRUCTURED_LOGGING") { Rails.env.production?.to_s } == "true"

    if log_to_stdout
      base = ActiveSupport::Logger.new($stdout)

      if structured
        base.formatter = Logging::SparcJsonFormatter.new
      else
        base.formatter = ActiveSupport::Logger::SimpleFormatter.new
      end

      # TaggedLogging must wrap the logger for config.log_tags to work at all;
      # the JSON formatter reads those tags back out as fields.
      config.logger = ActiveSupport::TaggedLogging.new(base)
    end

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
