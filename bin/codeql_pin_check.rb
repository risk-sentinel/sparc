#!/usr/bin/env ruby
# frozen_string_literal: true

# #1186 — a CodeQL disposition covers the results it names, and no others.
#
#   bin/codeql_pin_check.rb --register docs/compliance/sparc-findings.yml \
#     --sarif codeql-results.sarif --hdf hdf-results/codeql.hdf.json
#
# ── Why ────────────────────────────────────────────────────────────────────
#
# An HDF amendment override matches on `requirementId`, and CodeQL's SARIF
# converts to ONE requirement per RULE, holding every site the rule fires on.
# So a register entry for `rb/csrf-protection-disabled` suppresses the rule —
# the three reviewed sites, and any fourth someone adds tomorrow. That is the
# same hazard as raising the threshold, which #1186 rejected for exactly this
# reason.
#
# A register entry for a rule therefore lists the results it was reviewed
# against (`pinned_results`: path + CodeQL's `primaryLocationLineHash`), and
# this check fails the gate unless the live results for that rule are EXACTLY
# that set:
#
#   a result not pinned    -> an undispositioned instance. Fix it, or review
#                             it and pin it.
#   a pin with no result   -> a stale pin. The site was fixed or edited;
#                             retire or re-review it. An edited flagged line
#                             changes its hash, which is when a re-review is due.
#
# The line hash is CodeQL's own fingerprint: it survives unrelated edits that
# shift line numbers, and changes when the flagged line's text changes. The
# HDF carries only `path LINE n`, so the SARIF is read alongside it, and the
# HDF's result count for the rule is checked against the SARIF's — tying the
# fingerprints to the document the gate actually assesses.
#
# ── Pull requests run a PARTIAL scan ────────────────────────────────────
#
# On a pull request the CodeQL action runs DIFF-INFORMED analysis
# (`runs[].properties.incrementalMode` includes `diff-informed`): data-flow
# (`path-problem`) queries report only results inside the lines the PR changed.
# Measured on PR #1188: `rb/clear-text-storage-sensitive-data` returned 0 of its
# 5 pinned results, none of which the PR touched, while the non-data-flow CSRF
# rule returned all 3. So on a diff-informed scan an ABSENT pin means "outside
# this scan", not "fixed", and is reported as a notice. A PRESENT unpinned
# result is still a failure — anything the scan does report is inside the diff
# and must be dispositioned. The stale-pin rule is enforced on FULL scans (push
# to main, schedule), which is where a retired site would actually disappear.
#
# FAILS CLOSED: a missing or unreadable SARIF or HDF is an error, never a pass.
#
# NIST SP 800-53 Rev 5: RA-5 (vulnerability monitoring), CA-7 (continuous
# monitoring), SI-2.
require "json"
require "optparse"
require "set"
require "yaml"

SKIP_DISPOSITIONS = %w[remediated].freeze

def pinned_entries(register_path)
  YAML.load_file(register_path).fetch("findings", []).select do |f|
    f["pinned_results"] && !SKIP_DISPOSITIONS.include?(f["disposition"])
  end
end

# { rule_id => Set[[path, line_hash], ...] }
def sarif_results(sarif_path)
  sarif = JSON.parse(File.read(sarif_path))
  sarif.fetch("runs").each_with_object(Hash.new { |h, k| h[k] = Set.new }) do |run, acc|
    Array(run["results"]).each do |result|
      location = result.dig("locations", 0, "physicalLocation", "artifactLocation", "uri")
      line_hash = result.dig("partialFingerprints", "primaryLocationLineHash")
      raise "a #{result['ruleId']} result has no location or line hash — cannot pin it" unless location && line_hash

      acc[result["ruleId"]] << [ location, line_hash ]
    end
  end
end

# True when any run in the SARIF was a diff-informed (partial) analysis.
def diff_informed?(sarif_path)
  JSON.parse(File.read(sarif_path)).fetch("runs").any? do |run|
    run.dig("properties", "incrementalMode").to_s.split(",").map(&:strip).include?("diff-informed")
  end
end

def hdf_result_counts(hdf_path)
  hdf = JSON.parse(File.read(hdf_path))
  requirements = hdf["profiles"] ? hdf["profiles"].flat_map { |p| p["controls"] || [] } : hdf.fetch("baselines").flat_map { |b| b["requirements"] || [] }
  requirements.to_h { |r| [ r["id"], Array(r["results"]).size ] }
end

def check(register:, sarif:, hdf:)
  entries = pinned_entries(register)
  live = sarif_results(sarif)
  counts = hdf_result_counts(hdf)
  partial = diff_informed?(sarif)
  errors = []
  puts "codeql_pin_check: DIFF-INFORMED scan — absent pins are notices, not failures" if partial

  entries.each do |entry|
    rule = entry["cve_id"]
    pinned = Set.new(entry["pinned_results"].map { |p| [ p["path"], p["line_hash"] ] })
    found = live[rule]

    (found - pinned).sort.each do |path, hash|
      errors << "#{rule}: UNDISPOSITIONED result at #{path} (#{hash}) — the register entry covers only its pinned results; fix it or review and pin it"
    end
    (pinned - found).sort.each do |path, hash|
      if partial
        puts "::notice::#{rule}: pinned result #{path} (#{hash}) is outside this diff-informed scan — checked on the next full scan"
      else
        errors << "#{rule}: STALE pin #{path} (#{hash}) — no such result any more; retire it or re-review the edited line"
      end
    end
    if counts.fetch(rule, 0) != found.size
      errors << "#{rule}: the HDF holds #{counts.fetch(rule, 0)} result(s) but the SARIF #{found.size} — the fingerprints do not describe the assessed document"
    end
    puts "#{rule}: #{found.size} result(s), #{pinned.size} pinned#{' — exact match' if found == pinned}"
  end

  errors
end

if __FILE__ == $PROGRAM_NAME
  opts = {}
  OptionParser.new do |o|
    o.on("--register PATH") { |v| opts[:register] = v }
    o.on("--sarif PATH") { |v| opts[:sarif] = v }
    o.on("--hdf PATH") { |v| opts[:hdf] = v }
  end.parse!

  missing = %i[register sarif hdf].reject { |k| opts[k] && File.file?(opts[k]) }
  abort "codeql_pin_check: missing input(s): #{missing.map { |k| "--#{k} #{opts[k].inspect}" }.join(', ')} — failing closed" if missing.any?

  begin
    errors = check(register: opts[:register], sarif: opts[:sarif], hdf: opts[:hdf])
  rescue StandardError => e
    abort "codeql_pin_check: #{e.class}: #{e.message} — failing closed"
  end

  if errors.any?
    warn "CODEQL PIN CHECK FAILED:"
    errors.each { |e| warn "  - #{e}" }
    exit 1
  end
  puts "codeql pin check: every dispositioned rule's results match its pins"
end
