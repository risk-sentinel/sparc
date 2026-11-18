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

resultsets = ARGV
abort "no coverage resultsets given" if resultsets.empty?

# Every shard names its result "rspec-shard-<index>-of-<total>". A shard that
# passed but uploaded nothing would otherwise just lower the total, and the
# failure would read as "coverage fell" rather than "a shard is missing".
names = resultsets.flat_map { |path| JSON.parse(File.read(path)).keys }
shards = names.filter_map { |name| name[/\Arspec-shard-(\d+)-of-(\d+)\z/] && [ Integer(Regexp.last_match(1)), Integer(Regexp.last_match(2)) ] }
totals = shards.map(&:last).uniq
abort "coverage results are not shard results: #{names.inspect}" unless shards.size == names.size && totals.size == 1
missing = (0...totals.first).to_a - shards.map(&:first)
abort "coverage is missing shard(s) #{missing.join(', ')} of #{totals.first}" if missing.any?

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
