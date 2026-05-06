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

    # Minimum overall line coverage. Set at 70% to lock in today's
    # measured baseline (71.17% as of 2026-05-06) with a small buffer
    # to absorb run-to-run variance. Ratchet upward in follow-up PRs;
    # never downward (#367 ratchet policy).
    #
    # Per-file coverage gate (minimum_coverage_by_file) is intentionally
    # NOT enabled in this PR: 15 existing files measure at 0% line
    # coverage and would fail any non-zero per-file floor. Tracked in
    # follow-up issue: bring those files above 30%, then enable.
    #
    # Branch coverage (enable_coverage :branch) is also deferred -- not
    # measured today, so we don't have a baseline to set a floor against.
    # Track in follow-up: enable, measure, set floor.
    #
    # Threshold is enforced only when CI=true (full suite) so developers
    # running individual specs locally don't trip the floor on partial
    # runs. CI runs the full suite; the gate fires there.
    minimum_coverage 70 if ENV["CI"]
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
