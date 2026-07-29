#!/usr/bin/env ruby
# frozen_string_literal: true

# CI gate (#865): a FedRAMP deviation may not approve itself.
#
# `docs/compliance/sparc-findings.yml` lets a deferred finding carry a
# deviation whose risk_status is `deviation-approved`. That status suppresses
# the finding from the SAF threshold residual — so on a CRITICAL it is the
# difference between a red build and a green one. The approval that justifies
# it is the code-owner review on the pull request introducing it.
#
#   On a pull request : every finding whose deviation is `deviation-approved`
#                       AND which this PR adds or modifies must be covered by
#                       an approving code-owner review.
#   On main / push    : trusted — such entries could only arrive via an
#                       approved PR, because branch protection requires one.
#
# Unchanged approved deviations are NOT re-checked. They were approved when
# they landed; re-litigating them would make every unrelated PR depend on a
# review of work it did not touch.
#
# Why `reviewDecision` and not a CODEOWNERS name match:
# .github/CODEOWNERS assigns ownership to TEAMS (@risk-sentinel/sparc-admin),
# while reviews are submitted by individuals. Matching reviewer logins against
# the file would never succeed without resolving team membership through an
# org-scoped API call the default CI token may not be able to make. GitHub
# already computes the answer — `reviewDecision` is APPROVED only when the
# review requirements branch protection derives from CODEOWNERS are satisfied.
# That is precisely the question this gate asks.
#
# Exit 0 = every newly-approved deviation carries an approving review.
# Exit 1 = a deviation is self-approved, or approval could not be established.

require "yaml"
require "json"

REPO_ROOT = File.expand_path("../..", __dir__)
FINDINGS  = ENV.fetch("SPARC_FINDINGS_FILE", File.join(REPO_ROOT, "docs/compliance/sparc-findings.yml"))
EVENT     = ENV["GITHUB_EVENT_NAME"].to_s
PR_NUM    = ENV["SPARC_PR_NUMBER"].to_s
BASE_REF  = ENV.fetch("SPARC_BASE_REF", "origin/main")

def load_findings(source)
  data = YAML.safe_load(source, permitted_classes: [ Date ], aliases: true)
  return {} unless data.is_a?(Hash)

  Array(data["findings"]).each_with_object({}) do |f, acc|
    next unless f.is_a?(Hash) && f["cve_id"]
    acc[f["cve_id"]] = f
  end
end

def approved_deviation?(finding)
  finding.dig("deviation", "risk_status") == "deviation-approved"
end

# Findings whose approved-deviation state this change introduces or alters.
def newly_approved(head, base)
  head.each_with_object([]) do |(cve, finding), acc|
    next unless approved_deviation?(finding)

    before = base[cve]
    acc << cve if before.nil? || before["deviation"] != finding["deviation"]
  end
end

def pr_review_state
  raw = `gh pr view #{PR_NUM} --json reviewDecision,latestReviews 2>/dev/null`
  return [ nil, [] ] if raw.strip.empty?

  parsed = JSON.parse(raw)
  approvers = Array(parsed["latestReviews"])
              .select { |r| r["state"] == "APPROVED" }
              .filter_map { |r| r.dig("author", "login") }
  [ parsed["reviewDecision"], approvers ]
rescue JSON::ParserError
  [ nil, [] ]
end

abort "✗ findings file not found: #{FINDINGS}" unless File.exist?(FINDINGS)

head_findings = load_findings(File.read(FINDINGS))
base_source   = `git show #{BASE_REF}:docs/compliance/sparc-findings.yml 2>/dev/null`
base_findings = base_source.strip.empty? ? {} : load_findings(base_source)

pending = newly_approved(head_findings, base_findings)

if pending.empty?
  puts "✓ No newly-approved deviations in this change."
  exit 0
end

puts "Deviations newly marked `deviation-approved` by this change:"
pending.each do |cve|
  dev = head_findings[cve]["deviation"]
  puts "  - #{cve}  type=#{dev['type']}  severity=#{head_findings[cve]['severity']}"
end
puts

unless %w[pull_request pull_request_review].include?(EVENT)
  puts "✓ Not a pull-request event — approval is enforced by branch protection at merge."
  exit 0
end

if PR_NUM.empty?
  warn "✗ SPARC_PR_NUMBER is not set; cannot verify the review decision."
  exit 1
end

decision, approvers = pr_review_state

if decision == "APPROVED"
  puts "✓ Deviation approval satisfied — PR review decision is APPROVED."
  puts "  Approving reviewers: #{approvers.empty? ? '(not disclosed)' : approvers.join(', ')}"
  exit 0
end

warn "✗ DEVIATION NOT APPROVED"
warn ""
warn "  #{pending.size} deviation(s) are marked `deviation-approved`, which suppresses them"
warn "  from the threshold residual. On a CRITICAL that is the difference between a"
warn "  red build and a green one, so the approval must come from a code-owner review"
warn "  of this PR — a deviation cannot approve itself."
warn ""
warn "  PR review decision : #{decision || '(none — no review submitted yet)'}"
warn "  Approving reviewers: #{approvers.empty? ? '(none)' : approvers.join(', ')}"
warn ""
warn "  This check re-runs automatically when a review is submitted."
exit 1
