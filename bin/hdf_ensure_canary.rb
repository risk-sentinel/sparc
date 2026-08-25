#!/usr/bin/env ruby
# frozen_string_literal: true

# Ensure an HDF document carries a canary control recording its execution.
#
# WHY THIS EXISTS (#962, #985, #990)
#
# A scanner that ran and found nothing, and a scanner that never ran at all,
# produce byte-identical evidence: an HDF with zero controls. Every threshold
# band is `count > max`, so against zero controls every count is 0 and every
# band passes trivially. Measured on run 32840183630: gitleaks, brakeman and
# bundler-audit were all zero-control documents passing all-zero bands.
#
# For a secrets scanner that is the highest-consequence vacuous pass in the
# pipeline — "no secrets found" and "the secret scanner is broken" are the
# same green check.
#
# The fix is an execution record: one passing control naming the scanner, the
# commit, the ref and the run, asserting zero findings. It renders compliance
# 100 where an empty profile renders 0. It records that a scan RAN; it does
# not synthesise a finding.
#
# hdf-libs already does this natively — `hdf convert` on a clean gitleaks SARIF
# emits `gitleaks-no-findings`. This script supplies the same thing for the
# scanners still converted by saf (grype, cyclonedx, bundler-audit), whose
# converters emit an empty document instead. The shape here deliberately
# mirrors hdf-libs' so both paths look identical downstream.
#
# POSITIVE EVIDENCE ONLY
#
# This must only ever run where the scanner's input file existed and its
# conversion succeeded. That is what makes the canary evidence rather than
# decoration — if it were written unconditionally it would manufacture the
# very reassurance the gate is trying to test for, and the canary assertion in
# security_gate would become a tautology.
#
# Idempotent: a document that already has controls is left byte-identical.

require "json"
require "optparse"
require "time"

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: hdf_ensure_canary.rb --input FILE --scanner NAME [options]"

  opts.on("--input FILE", "HDF JSON file to inspect (modified in place)") { |v| options[:input] = v }
  opts.on("--output FILE", "Write here instead of in place") { |v| options[:output] = v }
  opts.on("--scanner NAME", "Scanner name for the canary control") { |v| options[:scanner] = v }
  opts.on("--version VERSION", "Scanner version, if known") { |v| options[:version] = v }
  opts.on("--commit SHA", "Commit the scan ran against") { |v| options[:commit] = v }
  opts.on("--ref REF", "Git ref the scan ran against") { |v| options[:ref] = v }
  opts.on("--run-url URL", "CI run URL") { |v| options[:run_url] = v }
  opts.on("-h", "--help") { puts opts; exit 0 }
end
parser.parse!

%i[input scanner].each do |required|
  next if options[required]

  warn "hdf_ensure_canary: --#{required} is required"
  warn parser
  exit 2
end

input = options[:input]
output = options[:output] || input

unless File.file?(input)
  warn "hdf_ensure_canary: #{input} does not exist"
  exit 2
end

begin
  doc = JSON.parse(File.read(input))
rescue JSON::ParserError => e
  # Deliberately fatal. An unparseable HDF must not be quietly left alone —
  # `saf validate threshold` exits 0 on input it cannot parse (CI-1), so a
  # malformed document that slipped past here would score as a clean pass.
  warn "hdf_ensure_canary: #{input} is not valid JSON: #{e.message}"
  exit 1
end

unless doc.is_a?(Hash)
  warn "hdf_ensure_canary: #{input} is not an HDF object"
  exit 1
end

# HDF v2 — `profiles[].controls[]`. v3 (`baselines[]`) is not handled: nothing
# in this pipeline gates on v3, because `saf validate threshold` cannot read it.
if doc.key?("baselines") && !doc.key?("profiles")
  warn "hdf_ensure_canary: #{input} is HDF v3 (baselines[]); expected v2 (profiles[])"
  exit 1
end

profiles = doc["profiles"]
profiles = [] unless profiles.is_a?(Array)

existing_controls = profiles.sum { |p| p.is_a?(Hash) && p["controls"].is_a?(Array) ? p["controls"].length : 0 }

if existing_controls.positive?
  # Already carries findings — those ARE the evidence it ran.
  File.write(output, JSON.pretty_generate(doc)) if output != input
  puts "hdf_ensure_canary: #{File.basename(input)} has #{existing_controls} control(s); unchanged"
  exit 0
end

scanner = options[:scanner]
scanner_label = options[:version] ? "#{scanner} #{options[:version]}" : scanner

provenance = []
provenance << "commit #{options[:commit]}" if options[:commit]
provenance << "ref #{options[:ref]}" if options[:ref]
suffix = provenance.empty? ? "" : " (#{provenance.join(', ')})"

desc = "#{scanner_label} ran and reported zero findings#{suffix}."

now = Time.now.utc.iso8601

canary = {
  "id" => "#{scanner}-no-findings",
  "title" => "No findings reported",
  "desc" => desc,
  "descriptions" => [ { "data" => desc, "label" => "default" } ],
  "impact" => 0,
  "refs" => (options[:run_url] ? [ { "url" => options[:run_url] } ] : []),
  "tags" => { "scanner" => scanner },
  "source_location" => {},
  # Mirrors hdf-libs: impact 0 with a passing result renders as `skipped` at
  # control level. Our threshold files band `failed.*` and `error.total`, so a
  # skipped control trips nothing — it is present to prove execution, not to
  # move a number.
  "status" => "skipped",
  "results" => [
    {
      "code_desc" => desc,
      "start_time" => now,
      "status" => "passed"
    }
  ]
}

if profiles.empty?
  doc["profiles"] = [ {
    "name" => scanner,
    "title" => "#{scanner} execution record",
    "controls" => [ canary ],
    "attributes" => [],
    "groups" => [],
    "supports" => []
  } ]
else
  target = profiles.first
  target["controls"] = [ canary ]
  # saf's converters name the profile after the FORMAT ("SARIF", "CycloneDX
  # BOM Report: ...") rather than the tool, which is why this evidence was
  # anonymous in the first place (#990). If the profile carries no usable
  # identity, state the scanner.
  target["name"] = scanner if target["name"].nil? || target["name"].to_s.strip.empty?
end

File.write(output, JSON.pretty_generate(doc))
puts "hdf_ensure_canary: #{File.basename(output)} had 0 controls; wrote #{scanner} execution record"
