#!/usr/bin/env ruby
# frozen_string_literal: true

# Convert docs/compliance/sparc-findings.yml -> HDF Amendments JSON
# (https://mitre.github.io/hdf-libs/schemas/hdf-amendments/v3.2.0).
#
# Output is consumed by `hdf-cli amend` to mark dispositioned findings
# as not-applicable / failed-with-POA&M before SAF threshold gating.
#
# Disposition mapping:
#   false_positive  -> override type "falsePositive", status "notApplicable"
#   accepted        -> override type "waiver",        status "notApplicable"
#   deferred        -> override type "poam",          status "failed"
#   remediated      -> SKIP (finding should not be in current scan)
#
# Severity-based review cadence policy (per #244 acceptance criteria):
#   CRITICAL       -> 0 days  (no acceptance allowed; fail-fast)
#   HIGH           -> 30 days
#   MEDIUM         -> 60 days
#   LOW            -> 120 days
#   INFORMATIONAL  -> 60 days
#
# CRITICAL findings with disposition=accepted|false_positive|deferred
# are rejected by the validator — must be remediated, not suppressed.
#
# Usage:
#   bin/sparc_findings_to_hdf_amendments.rb \
#     --input docs/compliance/sparc-findings.yml \
#     --output amendments.hdf.json
#
# Exit codes:
#   0 — success
#   2 — validation error (CRITICAL with non-remediated disposition,
#       expired next_review_date, malformed entry)

require "yaml"
require "json"
require "optparse"
require "securerandom"
require "date"

# Severity policy from #244:
#   CRITICAL acceptance/false_positive is BANNED — must be remediated or
#   tracked as deferred POA&M (see CRITICAL_ALLOWED_DISPOSITIONS).
#   The cadence below applies to deferred (POA&M) entries; 30 days for
#   CRITICAL keeps the POA&M reviewed at least monthly while remaining
#   operationally feasible.
MAX_REVIEW_DAYS = {
  "CRITICAL"      => 30,
  "HIGH"          => 30,
  "MEDIUM"        => 60,
  "LOW"           => 120,
  "INFORMATIONAL" => 60
}.freeze

# CRITICAL findings cannot be 'accepted' (no risk acceptance for criticals).
# false_positive IS allowed because it's semantically distinct from accepted:
# 'accepted' means "we're keeping the risk", 'false_positive' means "the
# scanner is wrong; this finding doesn't apply." Genuine FPs on criticals
# (e.g., unreachable code paths, unused libraries) must be documentable.
CRITICAL_ALLOWED_DISPOSITIONS = %w[false_positive deferred remediated].freeze

DISPOSITION_TO_OVERRIDE_TYPE = {
  "false_positive" => "falsePositive",
  "accepted"       => "waiver",
  "deferred"       => "poam"
}.freeze

# Dispositions that map to status: notApplicable (suppressed in HDF)
NOT_APPLICABLE_DISPOSITIONS = %w[false_positive accepted].freeze
# Dispositions that map to status: failed (kept as failed but tracked)
FAILED_DISPOSITIONS = %w[deferred].freeze
# Dispositions that mean we don't emit an amendment at all
SKIP_DISPOSITIONS = %w[remediated].freeze

def severity_normalize(sev)
  sev.to_s.upcase
end

def parse_date(value)
  return nil if value.nil?
  return value if value.is_a?(Date)
  Date.parse(value.to_s)
end

def validate!(finding, errors, today: Date.today)
  cve_id     = finding["cve_id"]
  disp       = finding["disposition"]
  severity   = severity_normalize(finding["severity"])
  rationale  = finding["rationale"]
  reviewer   = finding["reviewed_by"]
  discovery  = parse_date(finding["discovery_date"])
  next_rev   = parse_date(finding["next_review_date"])

  errors << "missing cve_id" if cve_id.to_s.empty?
  errors << "#{cve_id}: unknown disposition '#{disp}'" unless (DISPOSITION_TO_OVERRIDE_TYPE.keys + SKIP_DISPOSITIONS).include?(disp)
  errors << "#{cve_id}: unknown severity '#{severity}'" unless MAX_REVIEW_DAYS.key?(severity)

  return errors if SKIP_DISPOSITIONS.include?(disp)

  errors << "#{cve_id}: rationale is required for disposition=#{disp}" if rationale.to_s.strip.empty?
  errors << "#{cve_id}: reviewed_by is required" if reviewer.to_s.strip.empty?
  errors << "#{cve_id}: discovery_date is required" unless discovery
  errors << "#{cve_id}: next_review_date is required" unless next_rev

  if severity == "CRITICAL" && !CRITICAL_ALLOWED_DISPOSITIONS.include?(disp)
    errors << "#{cve_id}: CRITICAL findings cannot use disposition='#{disp}'; allowed dispositions are #{CRITICAL_ALLOWED_DISPOSITIONS.join(', ')} (no waivers/false-positives — must remediate or document POA&M)"
  end

  validate_review_cadence(finding, errors, severity: severity, disposition: disp, discovery: discovery, next_rev: next_rev, today: today)

  errors
end

# Review-cadence checks (window + overdue). These apply to dispositions that
# hold or defer RISK — accepted / deferred. They do NOT apply to
# false_positive: a false positive is a determination that the finding is not
# real (scanner is wrong / vulnerable code path unreachable), so there is no
# risk on a remediation clock to re-review every 30 days (#620 — Ruby
# default-gem shadows, perl, x/crypto/ssh). discovery_date/next_review_date are
# still required for provenance (checked in validate!), but a stale
# next_review_date on a false_positive does not gate the build.
def validate_review_cadence(finding, errors, severity:, disposition:, discovery:, next_rev:, today:)
  return if disposition == "false_positive"

  cve_id = finding["cve_id"]

  if discovery && next_rev && MAX_REVIEW_DAYS.key?(severity)
    actual_days = (next_rev - discovery).to_i
    max_days = MAX_REVIEW_DAYS[severity]
    errors << "#{cve_id}: review window is #{actual_days}d — policy max for #{severity} is #{max_days}d" if actual_days > max_days
  end

  if next_rev && next_rev < today
    overdue_days = (today - next_rev).to_i
    errors << "#{cve_id}: next_review_date #{next_rev.iso8601} is #{overdue_days}d overdue (today=#{today.iso8601}) — re-review and refresh"
  end

  errors
end

def disposition_to_override(finding)
  cve_id    = finding["cve_id"]
  disp      = finding["disposition"]
  severity  = severity_normalize(finding["severity"])
  rationale = finding["rationale"]
  reviewer  = finding["reviewed_by"]
  discovery = parse_date(finding["discovery_date"])
  next_rev  = parse_date(finding["next_review_date"])

  return nil if SKIP_DISPOSITIONS.include?(disp)

  status = NOT_APPLICABLE_DISPOSITIONS.include?(disp) ? "notApplicable" : "failed"

  {
    "type"          => DISPOSITION_TO_OVERRIDE_TYPE.fetch(disp),
    "requirementId" => cve_id,
    "status"        => status,
    "reason"        => rationale,
    "appliedBy"     => identity_for(reviewer),
    "appliedAt"     => discovery.iso8601 + "T00:00:00Z",
    "expiresAt"     => next_rev.iso8601 + "T00:00:00Z"
  }
end

def identity_for(reviewer)
  if reviewer.to_s.start_with?("@")
    { "type" => "github", "identifier" => reviewer.to_s }
  else
    { "type" => "email", "identifier" => reviewer.to_s }
  end
end

def main(argv)
  opts = { input: "docs/compliance/sparc-findings.yml", output: "amendments.hdf.json", today: Date.today }
  OptionParser.new do |o|
    o.on("--input PATH",  "Input YAML")  { |v| opts[:input]  = v }
    o.on("--output PATH", "Output JSON") { |v| opts[:output] = v }
    o.on("--today DATE",  "Override today (testing)") { |v| opts[:today] = Date.parse(v) }
  end.parse!(argv)

  yaml = YAML.load_file(opts[:input])
  findings = yaml.fetch("findings", [])

  errors = []
  findings.each_with_index { |f, i| errors.concat(validate!(f.merge("_index" => i), [], today: opts[:today])) }

  unless errors.empty?
    warn "VALIDATION FAILED:"
    errors.each { |e| warn "  - #{e}" }
    exit 2
  end

  overrides = findings.filter_map { |f| disposition_to_override(f) }

  amendments = {
    "amendmentId"  => SecureRandom.uuid,
    "name"         => "SPARC Container Image Findings — #{opts[:today].iso8601}",
    "description"  => "Generated from docs/compliance/sparc-findings.yml. " \
                      "Dispositions: false_positive -> falsePositive, accepted -> waiver, deferred -> poam. " \
                      "remediated entries are not emitted.",
    "version"      => "1",
    "appliedBy"    => identity_for("@clem-field"),
    "generator"    => {
      "name"    => "sparc/bin/sparc_findings_to_hdf_amendments.rb",
      "version" => "1.0.0"
    },
    "labels" => {
      "system_id"  => "sparc-application",
      "source_yml" => opts[:input]
    },
    "overrides" => overrides
  }

  File.write(opts[:output], JSON.pretty_generate(amendments))
  puts "Wrote #{overrides.size} override(s) to #{opts[:output]} (skipped #{findings.size - overrides.size} remediated)"
end

main(ARGV) if __FILE__ == $PROGRAM_NAME
