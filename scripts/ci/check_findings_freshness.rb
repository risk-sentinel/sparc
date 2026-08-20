#!/usr/bin/env ruby
# frozen_string_literal: true

# CI gate (#778): fail when a security-finding disposition's review date has
# lapsed.
#
# The sparc-findings.yml dispositions and the .trivyignore review dates are
# FedRAMP evidence, and docs/dev/issue_rules.md requires a review cadence — but
# nothing machine-checked it, so it drifted silently. The v1.12.2 audit (#770)
# found 31 overdue next_review_dates and 11 stale "remediated" entries still in
# the image, none flagged by CI. This is the automated backstop.
#
# Checks:
#   1. docs/compliance/sparc-findings.yml — every non-exempt finding's
#      next_review_date is in the future (grace window configurable).
#      false_positive dispositions are exempt (determined not-a-vuln; there is
#      no accepted-risk cadence to keep fresh).
#   2. `remediated` findings must be RETIRED, not carried (owner-decided
#      2026-08-20). See the note below.
#   3. Retired findings must carry proof of absence.
#   4. .trivyignore — each `# Reviewed: YYYY-MM-DD` is within the review window.
#
# ── Why `remediated` is retired rather than reviewed ────────────────────────
#
# A review cadence answers "is this accepted risk still acceptable?", which is a
# question about a LIVE disposition. It is the wrong question for something
# already fixed, and it generated most of the noise: 89 of 97 entries were
# `remediated`, so the file nagged about work that was done.
#
# But `remediated` cannot simply be exempted either. The v1.12.2 audit (#770)
# found ELEVEN entries claiming remediation while the package was still in the
# image — a claim nothing checked. Exempting the disposition would restore
# exactly that blind spot across 92% of the file.
#
# So a remediated finding leaves the active file entirely, and leaving requires
# EVIDENCE: `verified_absent_on` (the date a real scan of the shipping image
# found nothing) and `verified_by` (what scanned it). The active file then holds
# only live dispositions, which is what a cadence is for, and the scanner stays
# the source of truth for what is actually in the image.
#
# Retirement must be HARDER than review, or it becomes the escape hatch a
# lapsed date never was.
#
# The legacy Debian findings (sparc-findings.debian.yml) are intentionally NOT
# gated: the shipping image is UBI9 (#742), tracked by sparc-findings.yml; the
# Debian file is retained for history only.
#
# Exit 0 = everything fresh. Exit 1 = something overdue (with a clear summary of
# what and by how long, so the fix is "re-review + bump the date," not a mystery
# red X). Paths + "today" are ENV-overridable so the spec can prove both
# directions against fixtures.

require "yaml"
require "date"

REPO_ROOT = File.expand_path("../..", __dir__)

FINDINGS_FILE    = ENV.fetch("SPARC_FINDINGS_FILE", File.join(REPO_ROOT, "docs/compliance/sparc-findings.yml"))
TRIVYIGNORE_FILE = ENV.fetch("SPARC_TRIVYIGNORE_FILE", File.join(REPO_ROOT, ".trivyignore"))

# Grace after the review date before it counts as overdue (days).
GRACE_DAYS = Integer(ENV.fetch("FINDINGS_REVIEW_GRACE_DAYS", "0"))
# .trivyignore `# Reviewed:` staleness window (days) — issue_rules cadence.
TRIVYIGNORE_WINDOW_DAYS = Integer(ENV.fetch("TRIVYIGNORE_REVIEW_WINDOW_DAYS", "90"))
# Dispositions exempt from the review cadence.
EXEMPT_DISPOSITIONS = %w[false_positive].freeze
# Dispositions that must not live in the ACTIVE file at all — they are retired
# to the archive with proof of absence. See the note in the header.
RETIREABLE_DISPOSITIONS = %w[remediated].freeze
# Evidence a retired finding must carry, or retirement is just deletion.
RETIREMENT_EVIDENCE = %w[verified_absent_on verified_by].freeze

RETIRED_FILE = ENV.fetch("SPARC_FINDINGS_RETIRED_FILE",
                         File.join(REPO_ROOT, "docs/compliance/sparc-findings.retired.yml"))

def today
  ENV["FINDINGS_TODAY"] ? Date.parse(ENV["FINDINGS_TODAY"]) : Date.today
end

def parse_date(value)
  return value if value.is_a?(Date)

  Date.parse(value.to_s)
rescue ArgumentError, TypeError
  nil
end

def load_findings(path)
  return [] unless File.exist?(path)

  data = YAML.safe_load_file(path, permitted_classes: [ Date ], aliases: true)
  data.is_a?(Hash) ? Array(data["findings"]) : []
end

# → { overdue: [...], malformed: [...], unretired: [...] }
def check_findings
  result = { overdue: [], malformed: [], unretired: [] }
  return result unless File.exist?(FINDINGS_FILE)

  findings = load_findings(FINDINGS_FILE)
  cutoff = today - GRACE_DAYS

  findings.each do |f|
    next unless f.is_a?(Hash)

    id = f["cve_id"] || "(no cve_id)"
    if RETIREABLE_DISPOSITIONS.include?(f["disposition"].to_s)
      result[:unretired] << { id: id, disposition: f["disposition"] }
      next
    end

    next if EXEMPT_DISPOSITIONS.include?(f["disposition"].to_s)

    raw = f["next_review_date"]
    next if raw.nil? || raw.to_s.strip.empty?

    date = parse_date(raw)
    if date.nil?
      result[:malformed] << { id: id, value: raw }
    elsif date < cutoff
      result[:overdue] << { id: id, disposition: f["disposition"], date: date, days: (today - date).to_i }
    end
  end
  result
end

# → [ { line:, date:, age: } ]
def check_trivyignore
  stale = []
  return stale unless File.exist?(TRIVYIGNORE_FILE)

  File.foreach(TRIVYIGNORE_FILE).with_index(1) do |line, num|
    m = line.match(/#\s*Reviewed:\s*(\d{4}-\d{2}-\d{2})/)
    next unless m

    date = parse_date(m[1])
    next unless date

    age = (today - date).to_i
    stale << { line: num, date: date, age: age } if age > TRIVYIGNORE_WINDOW_DAYS
  end
  stale
end

# Retirement is only meaningful if it carries evidence; without this check,
# "retired" is a synonym for "deleted and forgotten".
# → [ { id:, missing: [...] } ]
def check_retired
  load_findings(RETIRED_FILE).filter_map do |f|
    next unless f.is_a?(Hash)

    missing = RETIREMENT_EVIDENCE.reject { |k| f[k].to_s.strip != "" }
    { id: f["cve_id"] || "(no cve_id)", missing: missing } if missing.any?
  end
end

findings = check_findings
unproven = check_retired
stale    = check_trivyignore
clean    = findings[:overdue].empty? && findings[:malformed].empty? &&
           findings[:unretired].empty? && unproven.empty? && stale.empty?

if clean
  puts "✓ Security-finding review dates are fresh (as of #{today})."
  puts "  #{File.basename(FINDINGS_FILE)}: all non-exempt next_review_dates are in the future (grace #{GRACE_DAYS}d)."
  puts "  #{File.basename(FINDINGS_FILE)}: no #{RETIREABLE_DISPOSITIONS.join('/')} findings left in the active file."
  puts "  #{File.basename(RETIRED_FILE)}: every retired finding carries #{RETIREMENT_EVIDENCE.join(' + ')}."
  puts "  #{File.basename(TRIVYIGNORE_FILE)}: all `# Reviewed:` dates within #{TRIVYIGNORE_WINDOW_DAYS} days."
  exit 0
end

warn "::error::Security-finding review dates are overdue — re-review each and bump the date."

unless findings[:overdue].empty?
  warn "\nOverdue #{File.basename(FINDINGS_FILE)} next_review_date (#{findings[:overdue].size}):"
  findings[:overdue].sort_by { |o| o[:date] }.each do |o|
    warn "  - #{o[:id]} [#{o[:disposition]}] due #{o[:date]} (#{o[:days]} day(s) ago)"
  end
end

unless findings[:unretired].empty?
  warn "\nRemediated findings still in the ACTIVE #{File.basename(FINDINGS_FILE)} (#{findings[:unretired].size}):"
  warn "  A fixed finding is RETIRED, not reviewed. Confirm the shipping image no longer"
  warn "  reports it, then move the entry to #{File.basename(RETIRED_FILE)} carrying"
  warn "  #{RETIREMENT_EVIDENCE.join(' + ')}. Do NOT just bump the date."
  findings[:unretired].first(20).each { |u| warn "  - #{u[:id]} [#{u[:disposition]}]" }
  warn "  ... and #{findings[:unretired].size - 20} more" if findings[:unretired].size > 20
end

unless unproven.empty?
  warn "\nRetired findings with no proof of absence in #{File.basename(RETIRED_FILE)} (#{unproven.size}):"
  warn "  Retirement without evidence is deletion. Add the missing keys."
  unproven.each { |u| warn "  - #{u[:id]}: missing #{u[:missing].join(', ')}" }
end

unless findings[:malformed].empty?
  warn "\nUnparseable next_review_date in #{File.basename(FINDINGS_FILE)} (#{findings[:malformed].size}):"
  findings[:malformed].each { |m| warn "  - #{m[:id]}: #{m[:value].inspect}" }
end

unless stale.empty?
  warn "\nStale `# Reviewed:` dates in #{File.basename(TRIVYIGNORE_FILE)} (> #{TRIVYIGNORE_WINDOW_DAYS} days):"
  stale.each { |s| warn "  - line #{s[:line]}: reviewed #{s[:date]} (#{s[:age]} days ago)" }
end

warn "\nProcess: docs/dev/issue_rules.md — review LIVE dispositions and bump the date; RETIRE remediated ones with proof."
exit 1
