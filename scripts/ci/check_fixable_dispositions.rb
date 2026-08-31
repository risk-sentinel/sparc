#!/usr/bin/env ruby
# frozen_string_literal: true

# Alert when a finding we ACCEPTED has since become fixable (#1075).
#
# THE GAP THIS CLOSES
#
# Every scan carries `Fixed Version` per finding, and all 16 register entries
# carry `fixed_version`. Nothing joined the two: `grep -rl fixed_version bin/
# script/` returned only spec files. So a deferral could renew on schedule, with
# its rationale intact and now false, indefinitely.
#
# `check_findings_freshness.rb` (#778) is adjacent and answers a DIFFERENT
# question — "has anyone looked at this lately?", not "is this fixable now?" A
# deferral can be perfectly fresh and sitting on a patch that shipped last week.
#
# The live case that prompted this: the register carries a `sqlite-libs` entry
# deferred with `fixed_version: 'none (Red Hat: Affected, no erratum)'`, and Red
# Hat has since shipped 3.34.1-11.el9_8.
#
# WHAT IT CHECKS
#
# For each register entry dispositioned `deferred` or `waiver` whose recorded
# `fixed_version` says no fix exists, look it up in the live scan. If the
# scanner now reports a fixed version, the reason for accepting it has expired.
#
# ADVISORY BY DEFAULT. `--strict` makes it exit non-zero. Blocking on day one
# would fail a release on a fix that has not been evaluated yet, which is the
# opposite of the intent — the point is to prompt a decision, not to force one
# at the worst moment.
#
# Usage:
#   check_fixable_dispositions.rb --findings docs/compliance/sparc-findings.yml \
#     --scan trivy-container-results.json [--strict]

require "json"
require "optparse"
require "yaml"

options = { strict: false }
parser = OptionParser.new do |opts|
  opts.banner = "Usage: check_fixable_dispositions.rb --findings FILE --scan FILE [--strict]"
  opts.on("--findings FILE", "docs/compliance/sparc-findings.yml") { |v| options[:findings] = v }
  opts.on("--scan FILE", "Trivy JSON scan of the image") { |v| options[:scan] = v }
  opts.on("--strict", "Exit non-zero when a disposition has become fixable") { options[:strict] = true }
  opts.on("-h", "--help") { puts opts; exit 0 }
end
parser.parse!

%i[findings scan].each do |required|
  next if options[required]

  warn "check_fixable_dispositions: --#{required} is required"
  warn parser
  exit 2
end

[ options[:findings], options[:scan] ].each do |path|
  next if File.file?(path)

  warn "check_fixable_dispositions: #{path} does not exist"
  exit 2
end

register = YAML.safe_load_file(options[:findings], permitted_classes: [ Date ])
findings = (register.is_a?(Hash) ? register["findings"] : nil) || []
if findings.empty?
  warn "check_fixable_dispositions: #{options[:findings]} carries no findings"
  exit 1
end

begin
  scan = JSON.parse(File.read(options[:scan]))
rescue JSON::ParserError => e
  warn "check_fixable_dispositions: #{options[:scan]} is not valid JSON: #{e.message}"
  exit 1
end

# Index the scan by vulnerability id -> fixed version (when the scanner has one).
fixed_by_id = {}
Array(scan["Results"]).each do |result|
  Array(result["Vulnerabilities"]).each do |vuln|
    id = vuln["VulnerabilityID"].to_s.strip
    fix = vuln["FixedVersion"].to_s.strip
    next if id.empty? || fix.empty?

    fixed_by_id[id] = { version: fix, package: vuln["PkgName"].to_s }
  end
end

if fixed_by_id.empty?
  # Not necessarily wrong — a clean image has nothing to report — but say so,
  # because "no alerts" and "nothing was examined" must not look identical.
  puts "check_fixable_dispositions: the scan reports no fixable findings at all " \
       "(#{options[:scan]}); nothing to cross-check."
end

# "No fix upstream" is how a deferral justifies itself. These are the phrasings
# the register uses; anything else is treated as a recorded fix already.
NOT_FIXED = /none available upstream|not-fixed|no erratum|none\b/i

ACCEPTED = %w[deferred waiver].freeze

expired = []
findings.each do |finding|
  next unless ACCEPTED.include?(finding["disposition"].to_s)

  recorded = finding["fixed_version"].to_s
  next unless recorded.empty? || recorded.match?(NOT_FIXED)

  # Match on EVERY identifier. #1001 re-keyed entries to the GHSA id the scanner
  # reports with the CVE in `also_known_as`; matching on one identifier only
  # silently misses them — measured at 2 of 16 while building #917's VEX
  # enrichment, and both were the most-discussed findings in the register.
  ids = [ finding["cve_id"], finding["also_known_as"] ].flatten.compact
              .map { |i| i.to_s.strip }.reject(&:empty?)
  hit_id = ids.find { |i| fixed_by_id.key?(i) }
  next unless hit_id

  expired << {
    ids: ids,
    matched: hit_id,
    package: finding["package"] || fixed_by_id[hit_id][:package],
    recorded: recorded.empty? ? "(none recorded)" : recorded,
    now_fixed_in: fixed_by_id[hit_id][:version],
    reviewed_by: finding["reviewed_by"],
    next_review_date: finding["next_review_date"]
  }
end

considered = findings.count { |f| ACCEPTED.include?(f["disposition"].to_s) }
puts "check_fixable_dispositions: #{considered} accepted finding(s) examined against " \
     "#{fixed_by_id.length} fixable scan finding(s)"

if expired.empty?
  puts "check_fixable_dispositions: no accepted finding has become fixable."
  exit 0
end

puts
puts "UPSTREAM FIX NOW AVAILABLE for #{expired.length} accepted finding(s):"
expired.each do |e|
  puts "  #{e[:matched]}  (#{e[:package]})"
  puts "    register says   : #{e[:recorded]}"
  puts "    scanner reports : fixed in #{e[:now_fixed_in]}"
  puts "    accepted by     : #{e[:reviewed_by] || 'unrecorded'}, next review #{e[:next_review_date] || 'unrecorded'}"
  puts "    -> the reason this was accepted has expired; remediate or re-state it"
end
puts

if options[:strict]
  warn "::error::#{expired.length} accepted finding(s) now have an upstream fix"
  exit 1
end

warn "::warning::#{expired.length} accepted finding(s) now have an upstream fix " \
     "(advisory — pass --strict to fail)"
exit 0
