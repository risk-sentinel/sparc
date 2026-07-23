require_relative "boot"

require "rails/all"

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
    config.autoload_lib(ignore: %w[assets tasks logging])

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
        require_relative "../lib/logging/sparc_json_formatter"
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
