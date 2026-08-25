#!/usr/bin/env ruby
# frozen_string_literal: true

# Drop SARIF results that the producing tool has already marked suppressed,
# so the security gate assesses the RESIDUAL rather than the raw scan.
#
# Why this exists
# ---------------
# SARIF 2.1.0 gives every result an optional `suppressions` array. Brakeman
# populates it from `config/brakeman.ignore`, carrying the full justification
# text and pointing at the ignore file as the suppression's location — the
# format working exactly as intended.
#
# `saf convert sarif2hdf` does not read that field. Every suppressed result is
# converted into a `failed` HDF control, so a finding that a reviewer has
# examined, justified and dispositioned arrives at `security_gate` looking
# identical to a brand-new one.
#
# Measured on main@a8991ae7 (#1048): `bin/brakeman --format sarif` emitted 5
# results, **all 5 suppressed and 0 live**, and the resulting HDF reported 1
# high + 1 low. A `failed.high.max: 0` band would therefore have blocked every
# build forever on four intentional, documented design decisions — including
# the per-service-account admin opt-in that AC-6 explicitly describes.
#
# Filtering here rather than loosening the band keeps the gate meaningful: it
# fires on NEW findings, which is the posture #987 asks for.
#
# Evidence is not lost. The unfiltered `*-sarif` artifacts are uploaded with
# 90-day retention and archived into the combined zip, and each suppression's
# justification lives in the reviewed, in-repo ignore file. Only the gate's
# INPUT is filtered — the same separation the `hdf amend` layer already applies
# to CVE dispositions.
#
# Usage
#   bin/sarif_drop_suppressed.rb --input x.sarif --output x.filtered.sarif
#   bin/sarif_drop_suppressed.rb --input x.sarif --check   # report only

require "json"
require "optparse"

options = { input: nil, output: nil, check: false }
OptionParser.new do |opts|
  opts.banner = "Usage: bin/sarif_drop_suppressed.rb --input FILE [--output FILE] [--check]"
  opts.on("-i", "--input FILE", "SARIF file to filter") { |v| options[:input] = v }
  opts.on("-o", "--output FILE", "Destination (defaults to in-place)") { |v| options[:output] = v }
  opts.on("--check", "Report counts without writing") { options[:check] = true }
end.parse!

abort "sarif_drop_suppressed: --input is required" unless options[:input]
abort "sarif_drop_suppressed: no such file: #{options[:input]}" unless File.exist?(options[:input])

sarif = JSON.parse(File.read(options[:input]))

# A result is suppressed when it carries at least one suppression whose status
# is not "rejected". SARIF allows a suppression to be proposed and then
# rejected by a reviewer; a rejected suppression means the finding still
# counts. Absent `status` means accepted (the common case, and what Brakeman
# emits).
def suppressed?(result)
  Array(result["suppressions"]).any? { |s| s["status"].to_s != "rejected" }
end

total = 0
dropped = 0
justifications = []

Array(sarif["runs"]).each do |run|
  results = Array(run["results"])
  total += results.length

  kept = results.reject do |r|
    next false unless suppressed?(r)

    dropped += 1
    justifications << {
      rule: r["ruleId"],
      location: r.dig("locations", 0, "physicalLocation", "artifactLocation", "uri"),
      line: r.dig("locations", 0, "physicalLocation", "region", "startLine")
    }
    true
  end

  run["results"] = kept
end

name = File.basename(options[:input])
warn "sarif_drop_suppressed: #{name}: #{total} result(s), #{dropped} suppressed, #{total - dropped} live"
justifications.each do |j|
  warn "  suppressed: #{j[:rule]} #{j[:location]}:#{j[:line]}"
end

exit 0 if options[:check]

File.write(options[:output] || options[:input], JSON.pretty_generate(sarif))
