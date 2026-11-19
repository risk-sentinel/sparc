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

# The logic lives in a module so the spec runs it in-process; the guard at the
# bottom is the command line.
module SpecShard
  DEFAULT_SECONDS = 0.2
  ROOT = File.expand_path("../..", __dir__)
  TIMINGS = File.join(__dir__, "spec_timings.json")

  # The files dealt into `total` shards: [{ seconds:, files: }, ...].
  def self.deal(files, timings, total)
    shards = Array.new(total) { { seconds: 0.0, files: [] } }
    files.sort_by { |f| [ -timings.fetch(f, DEFAULT_SECONDS), f ] }.each do |file|
      lightest = shards.min_by { |s| s[:seconds] }
      lightest[:files] << file
      lightest[:seconds] += timings.fetch(file, DEFAULT_SECONDS)
    end
    shards
  end

  def self.spec_files(root = ROOT)
    Dir.glob("spec/**/*_spec.rb", base: root).sort
  end

  # The command line; returns the exit status.
  def self.main(argv, out: $stdout, err: $stderr, root: ROOT, timings: JSON.parse(File.read(TIMINGS)))
    index, total = argv.first(2).map { |arg| Integer(arg, exception: false) }
    unless argv.size == 2 && index && total
      err.puts "usage: spec_shard.rb INDEX TOTAL"
      return 2
    end
    unless (0...total).cover?(index)
      err.puts "shard index #{index} is outside 0...#{total}"
      return 1
    end

    shard = deal(spec_files(root), timings, total)[index]
    err.puts format("shard %d of %d: %d files, about %.1f minutes of examples",
                    index + 1, total, shard[:files].size, shard[:seconds] / 60)
    out.puts shard[:files].sort
    0
  end
end

exit(SpecShard.main(ARGV)) if __FILE__ == $PROGRAM_NAME
