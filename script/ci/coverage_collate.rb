#!/usr/bin/env ruby
# frozen_string_literal: true

# Merges the coverage each test shard recorded into one report and applies the
# floor to the total:  script/ci/coverage_collate.rb coverage-shards/*/.resultset.json
#
# A shard runs only part of the suite, so its own coverage says nothing; the
# floor that spec/spec_helper.rb applies to a whole run is applied here instead.
# The filters, groups, formatters and floor below must match spec_helper.rb.
require "simplecov"
require "simplecov_json_formatter"

require "json"

# The logic lives in a module so the spec runs it in-process; the guard at the
# bottom is the command line.
module CoverageCollate
  SHARD_NAME = /\Arspec-shard-(\d+)-of-(\d+)\z/

  # What is wrong with the set of results, or nil when it is every shard of one
  # run. Every shard names its result "rspec-shard-<index>-of-<total>". A shard
  # that passed but uploaded nothing would otherwise just lower the total, and
  # the failure would read as "coverage fell" rather than "a shard is missing".
  def self.problem(resultsets)
    return "no coverage resultsets given" if resultsets.empty?

    names = resultsets.flat_map { |path| JSON.parse(File.read(path)).keys }
    shards = names.filter_map { |name| SHARD_NAME.match(name)&.captures&.map(&:to_i) }
    totals = shards.map(&:last).uniq
    return "coverage results are not shard results: #{names.inspect}" unless shards.size == names.size && totals.size == 1

    missing = (0...totals.first).to_a - shards.map(&:first)
    "coverage is missing shard(s) #{missing.join(', ')} of #{totals.first}" if missing.any?
  end

  # Writes coverage/ from the merged results. SimpleCov exits the process with
  # a failing status itself when the total is under the floor.
  def self.collate(resultsets)
    SimpleCov.collate resultsets, "rails" do
      formatter SimpleCov::Formatter::MultiFormatter.new([
        SimpleCov::Formatter::HTMLFormatter,
        SimpleCov::Formatter::JSONFormatter
      ])
      coverage_dir "coverage"
      skip "/spec/"
      skip "/config/"
      skip "/db/"
      group "Models", "app/models"
      group "Controllers", "app/controllers"
      group "Services", "app/services"
      group "Jobs", "app/jobs"
      group "Concerns", "app/models/concerns"
      minimum_coverage 70
    end
  end

  # The command line; returns the exit status.
  def self.main(argv, err: $stderr)
    if (problem = problem(argv))
      err.puts problem
      return 1
    end

    collate(argv)
    0
  end
end

exit(CoverageCollate.main(ARGV)) if __FILE__ == $PROGRAM_NAME
