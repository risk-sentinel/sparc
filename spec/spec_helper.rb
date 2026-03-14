if ENV["COVERAGE"]
  require "simplecov"
  require "simplecov_json_formatter"

  SimpleCov.start "rails" do
    # Output both JSON (for SCA/CI) and HTML (for local browsing)
    formatter SimpleCov::Formatter::MultiFormatter.new([
      SimpleCov::Formatter::HTMLFormatter,
      SimpleCov::Formatter::JSONFormatter
    ])

    # All output goes to coverage/ directory:
    #   coverage/index.html       — human-readable HTML report
    #   coverage/.resultset.json  — raw data
    #   coverage/coverage.json    — JSON report for SCA tools
    coverage_dir "coverage"

    add_filter "/spec/"
    add_filter "/config/"
    add_filter "/db/"
    add_group "Models", "app/models"
    add_group "Controllers", "app/controllers"
    add_group "Services", "app/services"
    add_group "Jobs", "app/jobs"
    add_group "Concerns", "app/models/concerns"
    minimum_coverage 50
  end
end

# See https://rubydoc.info/gems/rspec-core/RSpec/Core/Configuration
RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups

  # Run specs in random order to surface order dependencies
  config.order = :random

  # Seed global randomization so that running tests in the same order is
  # reproducible using `--seed 1234`
  Kernel.srand config.seed
end
