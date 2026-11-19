#!/usr/bin/env ruby
# frozen_string_literal: true

# Merges the coverage each test shard recorded into one report and applies the
# floor to the total:  script/ci/coverage_collate.rb coverage-shards/*/.resultset.json
#
# A shard runs only part of the suite, so its own coverage says nothing; the
# floor that spec/spec_helper.rb applies to a whole run is applied here instead.
# The filters, groups and floor below must match spec_helper.rb;
# spec/scripts/coverage_collate_spec.rb reads both and fails if they drift.
require "simplecov"
require "simplecov_json_formatter"

require "json"

# The logic lives in a module so the spec runs it in-process; the guard at the
# bottom is the command line.
module CoverageCollate
  SHARD_NAME = /\Arspec-shard-(\d+)-of-(\d+)\z/
  SKIPS = %w[/spec/ /config/ /db/].freeze
  GROUPS = {
    "Models" => "app/models",
    "Controllers" => "app/controllers",
    "Services" => "app/services",
    "Jobs" => "app/jobs",
    "Concerns" => "app/models/concerns"
  }.freeze
  MINIMUM_COVERAGE = 70

  # Every shard names its result "rspec-shard-<index>-of-<total>". A shard that
  # passed but uploaded nothing would otherwise just lower the total, and the
  # failure would read as "coverage fell" rather than "a shard is missing".
  # Returns what is wrong with these result names, or nil.
  def self.shard_problem(names)
    shards = names.filter_map { |name| (m = SHARD_NAME.match(name)) && [ Integer(m[1]), Integer(m[2]) ] }
    totals = shards.map(&:last).uniq
    return "coverage results are not shard results: #{names.inspect}" unless shards.size == names.size && totals.size == 1

    missing = (0...totals.first).to_a - shards.map(&:first)
    "coverage is missing shard(s) #{missing.join(', ')} of #{totals.first}" if missing.any?
  end

  def self.collate(resultsets)
    SimpleCov.collate resultsets, "rails" do
      formatter SimpleCov::Formatter::MultiFormatter.new([
        SimpleCov::Formatter::HTMLFormatter,
        SimpleCov::Formatter::JSONFormatter
      ])
      coverage_dir "coverage"
      SKIPS.each { |path| skip path }
      GROUPS.each { |name, path| group name, path }
      minimum_coverage MINIMUM_COVERAGE
    end
  end

  def self.main(argv, err: $stderr)
    if argv.empty?
      err.puts "no coverage resultsets given"
      return 1
    end

    problem = shard_problem(argv.flat_map { |path| JSON.parse(File.read(path)).keys })
    if problem
      err.puts problem
      return 1
    end

    collate(argv)
    0
  end
end

exit(CoverageCollate.main(ARGV)) if __FILE__ == $PROGRAM_NAME
