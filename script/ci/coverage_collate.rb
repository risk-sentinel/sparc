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

resultsets = ARGV
abort "no coverage resultsets given" if resultsets.empty?

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
