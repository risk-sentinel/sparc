# Progress must be visible while the suite runs, not only after it ends.
#
# Ruby leaves $stdout BLOCK-buffered when it is a pipe (CI) and only $stderr
# unbuffered. rspec's progress formatter writes single dots to stdout, so with
# ~6239 examples — under the 8192-byte buffer — the dots flush ONCE, at exit,
# while every warning appears instantly.
#
# The result is a CI log that shows all the alarming lines and none of the
# reassuring ones. Measured on run 33171386716: 20m50s of a 23m43s job emitted
# nothing at all, the longest gap being 12m54s. A passing run is indistinguishable
# from a hung one, which is precisely the "did this actually run?" ambiguity this
# milestone exists to remove.
$stdout.sync = true

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

    # #927 — `add_filter`/`add_group` are deprecated delegating aliases in
    # simplecov 1.1.1 (`skip`/`group`, same arguments, same behaviour). They
    # emitted eight [DEPRECATION] lines at the top of every run.
    skip "/spec/"
    skip "/config/"
    skip "/db/"
    group "Models", "app/models"
    group "Controllers", "app/controllers"
    group "Services", "app/services"
    group "Jobs", "app/jobs"
    group "Concerns", "app/models/concerns"

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
