#!/usr/bin/env ruby
# frozen_string_literal: true

# Convert docs/compliance/sparc-findings.yml -> HDF Amendments JSON
# (https://mitre.github.io/hdf-libs/schemas/hdf-amendments/v3.4.0).
#
# Output is consumed by `hdf-cli amend` to mark dispositioned findings
# as not-applicable / failed-with-POA&M before SAF threshold gating.
#
# Disposition mapping:
#   false_positive  -> override type "falsePositive", status "notApplicable"
#   accepted        -> override type "waiver",        status "notApplicable"
#   deferred        -> override type "poam",          status per deviation (below)
#   remediated      -> SKIP (finding should not be in current scan)
#
# FedRAMP deviation flow (#865)
# ─────────────────────────────
# A `deferred` finding may carry a `deviation:` block expressing the FedRAMP
# deviation vocabulary and the OSCAL risk lifecycle. The deviation's risk_status
# — not the disposition — decides whether the finding gates the build:
#
#   deviation-requested -> status "failed"          -> counts toward threshold.yml
#   deviation-approved  -> status "notApplicable"   -> suppressed from the residual
#
# That is the whole mechanic. the threshold files need no knowledge of deviations:
# an UNAPPROVED deviation on a CRITICAL still breaches failed.critical.max: 0
# and turns the build red, which is the intended behaviour. An APPROVED one is
# a signed-off risk decision and is suppressed.
#
# Approval is the code-owner review on the pull request that introduces it —
# see scripts/ci/check_deviation_approvals.rb, which refuses to let a deviation
# self-approve. The approval is also recorded in the register (approved_by /
# approved_in / approved_at) so the evidence lives in the artefact, not only in
# GitHub.
#
# FedRAMP deviation types:
#   false_positive         — the finding is WRONG; no vulnerability exists
#   risk_adjustment        — the vulnerability EXISTS but is rated higher than
#                            actual risk because mitigations are in place
#   operational_requirement— a weakness that must remain open
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
# scanner is wrong; this finding doesn't apply."
#
# #865: a real-but-mitigated CRITICAL is neither. It belongs in the POA&M as a
# `deferred` finding carrying a risk_adjustment deviation — which is what the
# FedRAMP vocabulary is for. Before that existed, such findings were recorded
# as false_positive because it was the only slot a CRITICAL could occupy, which
# asserted something untrue in auditable evidence and escaped the review
# cadence. Use a deviation instead.
CRITICAL_ALLOWED_DISPOSITIONS = %w[false_positive deferred remediated].freeze

# FedRAMP deviation types (all require Authorizing Official approval; here the
# code-owner review on the PR is that approval).
DEVIATION_FALSE_POSITIVE         = "false_positive"
DEVIATION_RISK_ADJUSTMENT        = "risk_adjustment"
DEVIATION_OPERATIONAL_REQUIREMENT = "operational_requirement"
DEVIATION_TYPES = [
  DEVIATION_FALSE_POSITIVE,
  DEVIATION_RISK_ADJUSTMENT,
  DEVIATION_OPERATIONAL_REQUIREMENT
].freeze

# OSCAL risk lifecycle states a deviation may occupy in this register. The full
# OSCAL vocabulary (open/investigating/remediating/closed) is modelled on
# PoamRisk/SarRisk; only the deviation states are meaningful here.
DEVIATION_REQUESTED = "deviation-requested"
DEVIATION_APPROVED  = "deviation-approved"
DEVIATION_RISK_STATUSES = [ DEVIATION_REQUESTED, DEVIATION_APPROVED ].freeze

DISPOSITION_DEFERRED = "deferred"

# An approved deviation must name who approved it, where, and when.
DEVIATION_APPROVAL_FIELDS = %w[approved_by approved_in approved_at].freeze

# How the approval was obtained. Recorded so the evidence states the strength of
# its own provenance rather than implying all approvals are equal.
#
#   review              — an authorised reviewer submitted an APPROVING REVIEW on
#                         the PR. The strong path: a distinct, attributable act.
#   admin-merge-bypass  — an admin merged past the red gate. GitHub forbids
#                         approving your own PR, so a single-admin repo cannot
#                         use the review path. Authority is verifiable; a
#                         separate approval event is not. Weaker, and declared
#                         so it can never be mistaken for the strong path.
DEVIATION_APPROVAL_MECHANISMS = %w[review admin-merge-bypass].freeze

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

  validate_deviation(finding, errors)
  validate_review_cadence(finding, errors, severity: severity, disposition: disp, discovery: discovery, next_rev: next_rev, today: today)

  errors
end

# #865 — validate the FedRAMP deviation block, if present.
#
# The rules encode distinctions that matter to an assessor reading the POA&M:
# a risk_adjustment with no stated mitigation is just an undocumented risk
# acceptance, and a false_positive that claims mitigations is contradicting
# itself (nothing to mitigate if the finding is wrong).
def validate_deviation(finding, errors)
  dev  = finding["deviation"]
  disp = finding["disposition"]

  return validate_missing_deviation(finding, errors) if dev.nil?

  unless disp == DISPOSITION_DEFERRED
    errors << "#{finding['cve_id']}: deviation blocks are only valid on disposition=#{DISPOSITION_DEFERRED} (got '#{disp}')"
    return errors
  end

  validate_deviation_vocabulary(finding, dev, errors)
  validate_deviation_by_type(finding, dev, errors)
  validate_deviation_approval(finding, dev, errors)
  validate_deviation_kev(finding, dev, errors)

  errors
end

# A deferred CRITICAL with no deviation block is an untriaged critical.
def validate_missing_deviation(finding, errors)
  if finding["disposition"] == DISPOSITION_DEFERRED && severity_normalize(finding["severity"]) == "CRITICAL"
    errors << "#{finding['cve_id']}: CRITICAL deferred findings require a deviation block (type + risk_status + mitigating_factors)"
  end
  errors
end

def validate_deviation_vocabulary(finding, dev, errors)
  cve_id = finding["cve_id"]
  unless DEVIATION_TYPES.include?(dev["type"])
    errors << "#{cve_id}: deviation.type must be one of #{DEVIATION_TYPES.join(', ')} (got '#{dev['type']}')"
  end
  unless DEVIATION_RISK_STATUSES.include?(dev["risk_status"])
    errors << "#{cve_id}: deviation.risk_status must be one of #{DEVIATION_RISK_STATUSES.join(', ')} (got '#{dev['risk_status']}')"
  end
  errors
end

# Per-type rules. These encode distinctions that matter to an assessor reading
# the POA&M: a risk_adjustment with no stated mitigation is just an
# undocumented risk acceptance, and a false_positive that claims mitigations is
# contradicting itself (nothing to mitigate if the finding is wrong).
def validate_deviation_by_type(finding, dev, errors)
  cve_id  = finding["cve_id"]
  factors = Array(dev["mitigating_factors"])

  case dev["type"]
  when DEVIATION_RISK_ADJUSTMENT
    validate_risk_adjustment(cve_id, factors, errors)
  when DEVIATION_FALSE_POSITIVE
    unless factors.empty?
      errors << "#{cve_id}: deviation.type=#{DEVIATION_FALSE_POSITIVE} must not carry mitigating_factors — a false positive is wrong, not mitigated"
    end
  when DEVIATION_OPERATIONAL_REQUIREMENT
    if dev["operational_justification"].to_s.strip.empty?
      errors << "#{cve_id}: deviation.type=#{DEVIATION_OPERATIONAL_REQUIREMENT} requires operational_justification"
    end
  else
    # Unknown type — already reported by validate_deviation_vocabulary; no
    # per-type rules can be applied, so there is nothing further to check.
    nil
  end

  errors
end

def validate_risk_adjustment(cve_id, factors, errors)
  if factors.empty?
    errors << "#{cve_id}: deviation.type=#{DEVIATION_RISK_ADJUSTMENT} requires at least one mitigating_factors entry — an RA with no stated mitigation is an undocumented risk acceptance"
  end
  if factors.any? { |f| mitigating_factor_description(f).empty? }
    errors << "#{cve_id}: every mitigating_factors entry needs a non-empty description"
  end
  errors
end

def mitigating_factor_description(factor)
  (factor.is_a?(Hash) ? factor["description"] : factor).to_s.strip
end

def validate_deviation_approval(finding, dev, errors)
  return errors unless dev["risk_status"] == DEVIATION_APPROVED

  missing = DEVIATION_APPROVAL_FIELDS.reject { |f| dev[f].to_s.strip != "" }
  errors << "#{finding['cve_id']}: deviation.risk_status=#{DEVIATION_APPROVED} requires #{missing.join(', ')}" unless missing.empty?

  mechanism = dev["approval_mechanism"]
  if mechanism && !DEVIATION_APPROVAL_MECHANISMS.include?(mechanism)
    errors << "#{finding['cve_id']}: deviation.approval_mechanism must be one of #{DEVIATION_APPROVAL_MECHANISMS.join(', ')} (got '#{mechanism}')"
  end

  errors
end

# #864 — a KEV-listed CVE is actively exploited in the wild; adjusting its risk
# downward demands more than the standard reachability argument.
def validate_deviation_kev(finding, dev, errors)
  return errors unless finding.dig("kev", "listed")
  return errors unless dev["type"] == DEVIATION_RISK_ADJUSTMENT
  return errors unless dev["kev_justification"].to_s.strip.empty?

  errors << "#{finding['cve_id']}: KEV-listed findings using #{DEVIATION_RISK_ADJUSTMENT} require an explicit kev_justification"
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

# Every identifier this finding may be reported under.
#
# #1048 — an override matches by `requirementId`, and different scanners key
# the SAME defect differently: grype reports GHSA ids, trivy reports CVE ids.
# #1001 re-keyed several register entries from CVE to GHSA to match what grype
# emits, preserving the old id in `also_known_as` — but nothing read that
# field, so those dispositions silently stopped matching any CVE-keyed
# scanner. That was invisible while the gate never ran; the moment the
# container is gated on trivy's (CVE-keyed) output, previously-dispositioned
# findings would resurface as undispositioned.
#
# Emitting one override per known identifier makes a disposition independent
# of which scanner's vocabulary happens to reach the gate. Overrides are keyed
# lookups, so ids that match nothing are inert.
def finding_identifiers(finding)
  ([ finding["cve_id"] ] + Array(finding["also_known_as"]))
    .map { |id| id.to_s.strip }
    .reject(&:empty?)
    .uniq
end

def disposition_to_override(finding)
  disp      = finding["disposition"]
  severity  = severity_normalize(finding["severity"])
  rationale = finding["rationale"]
  reviewer  = finding["reviewed_by"]
  discovery = parse_date(finding["discovery_date"])
  next_rev  = parse_date(finding["next_review_date"])

  return nil if SKIP_DISPOSITIONS.include?(disp)

  status = deviation_status(finding) ||
           (NOT_APPLICABLE_DISPOSITIONS.include?(disp) ? "notApplicable" : "failed")

  base = {
    "type"          => DISPOSITION_TO_OVERRIDE_TYPE.fetch(disp),
    "status"        => status,
    "reason"        => deviation_reason(finding, rationale),
    "appliedBy"     => identity_for(reviewer),
    "appliedAt"     => discovery.iso8601 + "T00:00:00Z",
    "expiresAt"     => next_rev.iso8601 + "T00:00:00Z"
  }

  finding_identifiers(finding).map { |id| base.merge("requirementId" => id) }
end

# #865 — the deviation's risk_status decides whether the finding gates.
# An approved deviation is a signed-off risk decision and is suppressed from the
# residual; an unapproved one stays `failed` so a CRITICAL still breaches
# threshold.yml's failed.critical.max: 0 and turns the build red.
# Returns nil when there is no deviation, so the caller falls back to the
# disposition-based mapping.
def deviation_status(finding)
  dev = finding["deviation"]
  return nil unless dev.is_a?(Hash)

  dev["risk_status"] == DEVIATION_APPROVED ? "notApplicable" : "failed"
end

# Fold the deviation's structured evidence into the override reason so the HDF
# artefact carries the justification, not just the verdict. The structured
# mitigating factors remain in the register for OSCAL risk/mitigating-factor
# export; the amendment schema has no richer field than `reason`.
def deviation_reason(finding, rationale)
  dev = finding["deviation"]
  return rationale unless dev.is_a?(Hash)

  parts = ["[FedRAMP deviation: #{dev['type']} / #{dev['risk_status']}]"]
  if (adjusted = dev["adjusted_severity"])
    parts << "Adjusted severity: #{adjusted}."
  end
  factors = Array(dev["mitigating_factors"]).map { |f| f.is_a?(Hash) ? f["description"] : f }.compact
  parts << "Mitigating factors: #{factors.join('; ')}." unless factors.empty?
  if dev["risk_status"] == DEVIATION_APPROVED
    parts << "Approved by #{dev['approved_by']} in #{dev['approved_in']} on #{dev['approved_at']}."
  end
  parts << rationale.to_s

  parts.join(" ")
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

  # disposition_to_override returns one override PER identifier the finding is
  # known by (cve_id + also_known_as), so this flattens rather than maps 1:1.
  emitted = findings.filter_map { |f| disposition_to_override(f) }
  overrides = emitted.flatten

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
  aliases = overrides.size - emitted.size
  puts "Wrote #{overrides.size} override(s) for #{emitted.size} finding(s) to #{opts[:output]} " \
       "(#{aliases} alias key(s); skipped #{findings.size - emitted.size} remediated)"
end

main(ARGV) if __FILE__ == $PROGRAM_NAME
