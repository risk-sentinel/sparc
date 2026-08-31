#!/usr/bin/env ruby
# frozen_string_literal: true

# Carry the disposition RATIONALE from sparc-findings.yml into an OpenVEX
# document, so an attested VEX says WHY a finding was accepted and not merely
# that it was.
#
# WHY THIS EXISTS (#917)
#
# #917 asks for a vulnerability predicate that captures "allow-listed items WITH
# their rationale, so acceptance decisions become attested evidence rather than
# tribal knowledge". The rationale is the point of the ask — a consumer can
# already see WHAT was found; what they cannot see is which findings we
# considered and why we shipped anyway.
#
# `hdf convert --from hdf-amendments --to openvex` gets most of the way there.
# It reads the amendments document (generated from the register) rather than the
# amended HDFs, so it is unaffected by #1067 — measured: 16 statements for 16
# register findings, correctly split 14 `affected` / 2 `not_affected`.
#
# But it DISCARDS the reasoning. Every statement comes out as:
#
#     "status": "not_affected", "justification": null,
#     "status_notes": "HDF override type: falsePositive"
#
# The register's actual rationale — paragraphs about re-keying, about a shadowed
# default gem whose vulnerable copy is on disk while a patched one is loaded —
# is gone. Attesting that document would publish the disposition without the
# decision, which is the half #917 exists for.
#
# WHAT THIS DOES NOT DO
#
# It does not invent an OpenVEX `justification`. That enum
# (vulnerable_code_not_present, vulnerable_code_not_in_execute_path, ...) is a
# specific technical claim about the vulnerability's reachability, and deriving
# it from a disposition label would be asserting something nobody decided. It is
# populated only when the register states it explicitly via `vex_justification`.
#
# Usage:
#   vex_enrich_rationale.rb --vex openvex.json --findings sparc-findings.yml \
#     [--output enriched.json]

require "json"
require "optparse"
require "yaml"

options = {}
parser = OptionParser.new do |opts|
  opts.banner = "Usage: vex_enrich_rationale.rb --vex FILE --findings FILE [--output FILE]"
  opts.on("--vex FILE", "OpenVEX document from `hdf convert --to openvex`") { |v| options[:vex] = v }
  opts.on("--findings FILE", "docs/compliance/sparc-findings.yml") { |v| options[:findings] = v }
  opts.on("--output FILE", "Write here (default: in place)") { |v| options[:output] = v }
  opts.on("-h", "--help") { puts opts; exit 0 }
end
parser.parse!

%i[vex findings].each do |required|
  next if options[required]

  warn "vex_enrich_rationale: --#{required} is required"
  warn parser
  exit 2
end

vex_path = options[:vex]
out_path = options[:output] || vex_path

[ vex_path, options[:findings] ].each do |path|
  next if File.file?(path)

  warn "vex_enrich_rationale: #{path} does not exist"
  exit 2
end

begin
  vex = JSON.parse(File.read(vex_path))
rescue JSON::ParserError => e
  warn "vex_enrich_rationale: #{vex_path} is not valid JSON: #{e.message}"
  exit 1
end

register = YAML.safe_load_file(options[:findings], permitted_classes: [ Date ])
findings = register.is_a?(Hash) ? (register["findings"] || []) : []
if findings.empty?
  warn "vex_enrich_rationale: #{options[:findings]} carries no findings"
  exit 1
end

# Index by every identifier a finding is known by. #1001 re-keyed entries to the
# GHSA id the scanner reports and kept the CVE in `also_known_as`; a lookup on
# one identifier only would silently miss half the register — which is exactly
# the defect that made amendment overrides no-ops before they were keyed on both.
by_id = {}
findings.each do |finding|
  [ finding["cve_id"], finding["also_known_as"] ].flatten.compact.each do |id|
    by_id[id.to_s.strip] = finding unless id.to_s.strip.empty?
  end
end

statements = vex["statements"]
unless statements.is_a?(Array)
  warn "vex_enrich_rationale: #{vex_path} has no statements[] — is it an OpenVEX document?"
  exit 1
end

enriched = 0
unmatched = []

statements.each do |statement|
  name = statement.dig("vulnerability", "name")
  finding = by_id[name.to_s.strip]
  unless finding
    unmatched << name
    next
  end

  rationale = finding["rationale"].to_s.strip
  next if rationale.empty?

  # Preserve what hdf-libs wrote (the override type) and append the decision, so
  # the machine-readable label and the human reasoning both survive.
  existing = statement["status_notes"].to_s.strip
  parts = []
  parts << existing unless existing.empty?
  parts << rationale
  statement["status_notes"] = parts.join("\n\n")

  # Provenance for the decision itself. A consumer reading an accepted finding
  # should be able to see who accepted it and when it is next due for review,
  # not just the prose.
  %w[reviewed_by discovery_date next_review_date nist_control deviation].each do |field|
    value = finding[field]
    next if value.nil? || value.to_s.strip.empty?

    (statement["sparc"] ||= {})[field] = value.to_s
  end

  # Only ever taken from the register — never derived from the disposition.
  justification = finding["vex_justification"].to_s.strip
  statement["justification"] = justification unless justification.empty?

  enriched += 1
end

if enriched.zero?
  warn "vex_enrich_rationale: matched no statements to the register — refusing " \
       "to write a document that claims enrichment it did not perform. " \
       "VEX ids: #{statements.map { |s| s.dig('vulnerability', 'name') }.compact.first(5).inspect}"
  exit 1
end

File.write(out_path, JSON.pretty_generate(vex))
puts "vex_enrich_rationale: enriched #{enriched}/#{statements.length} statement(s) from #{findings.length} register finding(s)"
warn "vex_enrich_rationale: no register entry for #{unmatched.inspect}" unless unmatched.empty?
