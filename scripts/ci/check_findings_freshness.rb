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
#   2. .trivyignore — each `# Reviewed: YYYY-MM-DD` is within the review window.
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

def today
  ENV["FINDINGS_TODAY"] ? Date.parse(ENV["FINDINGS_TODAY"]) : Date.today
end

def parse_date(value)
  return value if value.is_a?(Date)

  Date.parse(value.to_s)
rescue ArgumentError, TypeError
  nil
end

# → { overdue: [...], malformed: [...] }
def check_findings
  result = { overdue: [], malformed: [] }
  return result unless File.exist?(FINDINGS_FILE)

  data = YAML.safe_load_file(FINDINGS_FILE, permitted_classes: [ Date ], aliases: true)
  findings = data.is_a?(Hash) ? Array(data["findings"]) : []
  cutoff = today - GRACE_DAYS

  findings.each do |f|
    next unless f.is_a?(Hash)
    next if EXEMPT_DISPOSITIONS.include?(f["disposition"].to_s)

    raw = f["next_review_date"]
    id  = f["cve_id"] || "(no cve_id)"
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

findings = check_findings
stale    = check_trivyignore
clean    = findings[:overdue].empty? && findings[:malformed].empty? && stale.empty?

if clean
  puts "✓ Security-finding review dates are fresh (as of #{today})."
  puts "  #{File.basename(FINDINGS_FILE)}: all non-exempt next_review_dates are in the future (grace #{GRACE_DAYS}d)."
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

unless findings[:malformed].empty?
  warn "\nUnparseable next_review_date in #{File.basename(FINDINGS_FILE)} (#{findings[:malformed].size}):"
  findings[:malformed].each { |m| warn "  - #{m[:id]}: #{m[:value].inspect}" }
end

unless stale.empty?
  warn "\nStale `# Reviewed:` dates in #{File.basename(TRIVYIGNORE_FILE)} (> #{TRIVYIGNORE_WINDOW_DAYS} days):"
  stale.each { |s| warn "  - line #{s[:line]}: reviewed #{s[:date]} (#{s[:age]} days ago)" }
end

warn "\nProcess: docs/dev/issue_rules.md — re-review, then bump next_review_date / `# Reviewed:`."
exit 1
