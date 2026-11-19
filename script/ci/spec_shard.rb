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

# The logic lives in a module so spec/scripts/spec_shard_spec.rb runs it
# in-process; the guard at the bottom is the command line.
module SpecShard
  DEFAULT_SECONDS = 0.2
  ROOT = File.expand_path("../..", __dir__)
  TIMINGS = File.join(__dir__, "spec_timings.json")

  # The shards, each { seconds:, files: }, for `files` dealt over `total`.
  def self.assign(files, timings, total)
    shards = Array.new(total) { { seconds: 0.0, files: [] } }
    files.sort_by { |f| [ -timings.fetch(f, DEFAULT_SECONDS), f ] }.each do |file|
      lightest = shards.min_by { |s| s[:seconds] }
      lightest[:files] << file
      lightest[:seconds] += timings.fetch(file, DEFAULT_SECONDS)
    end
    shards
  end

  def self.spec_files(root)
    Dir.chdir(root) { Dir["spec/**/*_spec.rb"] }.sort
  end

  def self.main(argv, out: $stdout, err: $stderr, root: ROOT, timings_path: TIMINGS)
    index = Integer(argv.fetch(0))
    total = Integer(argv.fetch(1))
    unless (0...total).cover?(index)
      err.puts "shard index #{index} is outside 0...#{total}"
      return 1
    end

    shards = assign(spec_files(root), JSON.parse(File.read(timings_path)), total)
    err.puts format("shard %d of %d: %d files, about %.1f minutes of examples",
                    index + 1, total, shards[index][:files].size, shards[index][:seconds] / 60)
    out.puts shards[index][:files].sort
    0
  end
end

exit(SpecShard.main(ARGV)) if __FILE__ == $PROGRAM_NAME
