#!/usr/bin/env ruby
# frozen_string_literal: true

# Translate bundler-audit JSON output into HDF (Heimdall Data Format) so that
# dependency advisories reach `security_gate` like every other scanner.
#
# Why this exists
# ---------------
# `security.yml` runs bundler-audit, writes `bundler-audit-results.json`, and
# uploads it as a 90-day artifact. That artifact was the ONLY one of thirteen
# downloaded by `normalize_hdf` with no `saf convert ... 2hdf` call — it was
# fetched purely so it could be copied into the archive zip. With no HDF, it
# reached no threshold, so nothing ever assessed it (#1048).
#
# GHSA-mvxr-6m87-mv2q (`mail` 2.9.0) rode 85 green `security.yml` runs into
# `main` on exactly that gap, 8 of them merges.
#
# Why in-repo rather than upstream
# --------------------------------
# `@mitre/saf` 1.6.0 — the version this repository pins, and the latest
# published release — has 37 converters. None of them reads bundler-audit;
# the nearest neighbours are `dependency_track2hdf`, `snyk2hdf` and `zap2hdf`.
# Measured against the pinned CLI, not assumed. Writing `bundleraudit2hdf`
# upstream in mitre/hdf-converters is the better long-term home and would
# benefit every Ruby shop, but it moves at upstream cadence and the gate is
# open now. There is direct in-repo precedent for this shape of translation:
# `bin/sparc_findings_to_hdf_amendments.rb`, which `security_gate` already
# shells out to. Retire this script if an upstream converter lands.
#
# Usage
#   bin/bundler_audit_to_hdf.rb --input bundler-audit-results.json \
#                               --output hdf-results/bundler-audit.hdf.json
#
# Exit status is 0 whenever translation succeeds, INCLUDING when advisories
# were found. This script's job is to produce evidence, not to render a
# verdict — the verdict belongs to `saf validate threshold` against
# `docs/compliance/thresholds/bundler-audit.yml`. That separation is the whole
# point of #1048: scans produce artifacts, a gate assesses them, and a
# disposition in `docs/compliance/sparc-findings.yml` can amend them. A
# converter that exited non-zero on findings would bypass the disposition
# layer and re-create the problem it is fixing.

require "json"
require "optparse"
require "digest"
require "fileutils"
require "time"

options = { input: nil, output: nil }
OptionParser.new do |opts|
  opts.banner = "Usage: bin/bundler_audit_to_hdf.rb --input FILE --output FILE"
  opts.on("-i", "--input FILE", "bundler-audit JSON results") { |v| options[:input] = v }
  opts.on("-o", "--output FILE", "HDF JSON destination") { |v| options[:output] = v }
end.parse!

abort "bundler_audit_to_hdf: --input is required" unless options[:input]
abort "bundler_audit_to_hdf: --output is required" unless options[:output]
abort "bundler_audit_to_hdf: no such file: #{options[:input]}" unless File.exist?(options[:input])

raw = File.read(options[:input])
begin
  report = JSON.parse(raw)
rescue JSON::ParserError => e
  abort "bundler_audit_to_hdf: #{options[:input]} is not valid JSON: #{e.message}"
end

# bundler-audit criticality -> HDF impact.
#
# HDF impact drives the severity bucket `saf validate threshold` counts against
# (>=0.9 critical, >=0.7 high, >=0.4 medium, >=0.1 low, else none), so this
# mapping IS the gating policy for dependency advisories. Prefer the advisory's
# CVSS base score when it carries one — it is the finer-grained signal and
# keeps us consistent with how container scanners are scored — and fall back to
# the coarse `criticality` label when it does not.
CRITICALITY_IMPACT = {
  "critical" => 1.0,
  "high" => 0.7,
  "medium" => 0.5,
  "low" => 0.3,
  "none" => 0.0,
  "unknown" => 0.5 # an unrated advisory is not a safe advisory; treat as medium
}.freeze

def impact_for(advisory)
  score = advisory["cvss_v3"] || advisory["cvss_v2"]
  return (score.to_f / 10.0).round(2).clamp(0.0, 1.0) if score.to_s =~ /\A\d+(\.\d+)?\z/ && score.to_f.positive?

  CRITICALITY_IMPACT.fetch(advisory["criticality"].to_s.downcase, 0.5)
end

results = report["results"] || []

controls = results.map do |result|
  advisory = result["advisory"] || {}
  gem_info = result["gem"] || {}

  gem_name    = gem_info["name"].to_s
  gem_version = gem_info["version"].to_s
  # bundler-audit emits `id` as the advisory's primary identifier (a GHSA or
  # CVE); keep `cve` as an alternate so an entry keyed either way in
  # sparc-findings.yml can be matched by `hdf amend`.
  advisory_id = (advisory["id"] || advisory["cve"] || advisory["ghsa"]).to_s
  patched     = Array(advisory["patched_versions"]).join(", ")
  unaffected  = Array(advisory["unaffected_versions"]).join(", ")

  desc = []
  desc << advisory["description"].to_s.strip unless advisory["description"].to_s.strip.empty?
  desc << "Gem: #{gem_name} #{gem_version}"
  desc << "Patched versions: #{patched}" unless patched.empty?
  desc << "Unaffected versions: #{unaffected}" unless unaffected.empty?
  desc << "Advisory: #{advisory["url"]}" unless advisory["url"].to_s.empty?

  {
    "tags" => {
      # RA-5 Vulnerability Monitoring and Scanning; SI-2 Flaw Remediation.
      # Matches how docs/compliance/nist-sp800-53-rev5-mapping.md already
      # attributes bundler-audit coverage.
      "nist" => %w[RA-5 SI-2],
      "cci" => %w[CCI-001643 CCI-002605],
      "gem" => gem_name,
      "gem_version" => gem_version
    },
    "refs" => (advisory["url"].to_s.empty? ? [] : [ { "url" => advisory["url"] } ]),
    "source_location" => { "ref" => "Gemfile.lock", "line" => 0 },
    "title" => advisory["title"].to_s.strip.empty? ? "#{gem_name} #{gem_version}" : advisory["title"].to_s.strip,
    "id" => advisory_id.empty? ? "#{gem_name}-#{gem_version}" : advisory_id,
    "desc" => desc.join("\n"),
    "impact" => impact_for(advisory),
    "code" => JSON.pretty_generate(result),
    "results" => [
      {
        "status" => "failed",
        "code_desc" => "#{gem_name} #{gem_version} is affected by #{advisory_id}; " \
                       "patched versions: #{patched.empty? ? "none published" : patched}",
        "message" => "Gemfile.lock resolves #{gem_name} #{gem_version}",
        "start_time" => report["created_at"].to_s
      }
    ]
  }
end

hdf = {
  "platform" => {
    "name" => "Heimdall Tools",
    "release" => "2.13.0",
    "target_id" => "bundler-audit"
  },
  "version" => "2.13.0",
  "statistics" => {},
  "profiles" => [
    {
      "name" => "bundler-audit",
      "version" => report["version"].to_s,
      "title" => "Ruby dependency advisories (bundler-audit)",
      "maintainer" => "SPARC",
      "summary" => "bundler-audit #{report["version"]} against Gemfile.lock",
      "license" => nil,
      "copyright" => nil,
      "copyright_email" => nil,
      "supports" => [],
      "attributes" => [],
      "groups" => [],
      "status" => "loaded",
      "sha256" => Digest::SHA256.hexdigest(raw),
      "controls" => controls
    }
  ],
  "passthrough" => {
    "auxiliary_data" => [
      {
        "name" => "bundler-audit",
        "data" => {
          "version" => report["version"],
          "created_at" => report["created_at"],
          "finding_count" => results.length
        }
      }
    ]
  }
}

FileUtils.mkdir_p(File.dirname(options[:output]))
File.write(options[:output], JSON.pretty_generate(hdf))

warn "bundler_audit_to_hdf: #{results.length} advisory finding(s) -> #{options[:output]}"
