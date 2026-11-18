#!/usr/bin/env ruby
# frozen_string_literal: true

# Prints the spec files one CI shard runs:  script/ci/spec_shard.rb INDEX TOTAL
#
# Every spec file lands in exactly one shard. Files are dealt slowest first to
# whichever shard is lightest so far, using the measured seconds in
# spec_timings.json (files that take under a second are not listed there and
# count as DEFAULT_SECONDS). A new or renamed file needs no entry: it is still
# assigned, just weighted as a quick one until the table is refreshed.
require "json"

DEFAULT_SECONDS = 0.2

index = Integer(ARGV.fetch(0))
total = Integer(ARGV.fetch(1))
abort "shard index #{index} is outside 0...#{total}" unless (0...total).cover?(index)

root = File.expand_path("../..", __dir__)
timings = JSON.parse(File.read(File.join(__dir__, "spec_timings.json")))
files = Dir.chdir(root) { Dir["spec/**/*_spec.rb"] }.sort

shards = Array.new(total) { { seconds: 0.0, files: [] } }
files.sort_by { |f| [ -timings.fetch(f, DEFAULT_SECONDS), f ] }.each do |file|
  lightest = shards.min_by { |s| s[:seconds] }
  lightest[:files] << file
  lightest[:seconds] += timings.fetch(file, DEFAULT_SECONDS)
end

warn format("shard %d of %d: %d files, about %.1f minutes of examples",
            index + 1, total, shards[index][:files].size, shards[index][:seconds] / 60)
puts shards[index][:files].sort
