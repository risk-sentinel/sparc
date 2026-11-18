#!/usr/bin/env ruby
# frozen_string_literal: true

# Mark the matches a grype ignore rule suppressed as not applicable, explicitly.
#
# WHY THIS EXISTS (#1368)
#
# SAF's `convert anchoregrype2hdf` writes each of grype's `ignoredMatches` as a
# control `Grype-Ignored-Match/<id>` at impact 0, with a `failed` result. Up to
# hdf-cli 3.7.2 an impact of 0 meant `notApplicable`, so the v3 conversion in
# security_gate reported these as suppressed. hdf-cli 3.8.0 dropped that rule
# (an impact of 0 no longer decides a status), so the same document came out
# as 89 failed instead of 67 failed and 22 not applicable (measured 2026-11-18
# on run 44369358364's grype-container scan). The gate still passed, because
# its bands count by impact, but the evidence said a suppressed match failed.
#
# hdf-cli 3.8.0 keeps one translation: an InSpec-style control scored 0 whose
# result is `skipped` becomes an explicit `notApplicable`. This script states
# that, with the reason, for exactly the controls SAF built from
# `ignoredMatches`. It changes nothing else, so a real match is never touched.
#
# Idempotent; a document with no ignored matches is left byte-identical.
#
#   NIST RA-5, SI-2

require "json"
require "optparse"

# The logic lives in a module so the spec runs it in-process; the guard at the
# bottom is the command line.
module HdfMarkGrypeIgnored
  PREFIX = "Grype-Ignored-Match/"
  REASON = "Suppressed by a grype ignore rule; see the rule in this result's message."

  # Marks every result of every ignored-match control; returns how many changed.
  def self.mark!(doc)
    marked = 0
    Array(doc["profiles"]).each do |profile|
      Array(profile["controls"]).each do |control|
        next unless control["id"].to_s.start_with?(PREFIX)

        Array(control["results"]).each do |result|
          next if result["status"] == "skipped" && result["skip_message"] == REASON

          result["status"] = "skipped"
          result["skip_message"] = REASON
          marked += 1
        end
      end
    end
    marked
  end

  # Reads `input`, writes the marked document to `output` (default: in place),
  # leaving an unchanged in-place file byte-identical. Returns the count.
  def self.run(input:, output: nil)
    raw = File.read(input)
    doc = JSON.parse(raw)
    marked = mark!(doc)
    output ||= input
    File.write(output, marked.zero? && output == input ? raw : JSON.pretty_generate(doc))
    marked
  end

  # The command line; returns the exit status.
  def self.main(argv, out: $stdout, err: $stderr)
    options = {}
    OptionParser.new do |opts|
      opts.banner = "Usage: hdf_mark_grype_ignored.rb --input FILE [--output FILE]"
      opts.on("--input FILE", "HDF v2 JSON from saf convert anchoregrype2hdf (modified in place)") { |v| options[:input] = v }
      opts.on("--output FILE", "Write here instead of in place") { |v| options[:output] = v }
    end.parse!(argv.dup)

    unless options[:input]
      err.puts "hdf_mark_grype_ignored: --input is required"
      return 2
    end

    marked = run(input: options[:input], output: options[:output])
    out.puts "hdf_mark_grype_ignored: #{File.basename(options[:input])}: " \
             "#{marked} ignored-match result(s) marked not applicable"
    0
  end
end

exit(HdfMarkGrypeIgnored.main(ARGV)) if __FILE__ == $PROGRAM_NAME
