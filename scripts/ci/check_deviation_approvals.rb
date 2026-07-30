#!/usr/bin/env ruby
# frozen_string_literal: true

# CI gate (#865): a FedRAMP deviation may not approve itself.
#
# `docs/compliance/sparc-findings.yml` lets a deferred finding carry a
# deviation. Its risk_status decides whether the finding gates the build:
# `deviation-requested` emits `failed` (a CRITICAL then breaches
# threshold.yml's failed.critical.max: 0), `deviation-approved` emits
# `notApplicable` and is suppressed from the residual.
#
# So `deviation-approved` is a powerful claim, and this gate refuses to take it
# on trust. Two rules:
#
#   1. A deviation still `deviation-requested` fails the gate. That is the
#      intended resting state of a PR awaiting an Authorizing Official — red
#      blocks the merge until an admin decides.
#
#   2. A deviation marked `deviation-approved` by this PR must be corroborated:
#      the recorded approved_by must have actually submitted an APPROVING
#      REVIEW on this PR, and must hold admin/maintain on the repo. Hand-typing
#      the approval fields cannot satisfy this, because the review either
#      exists in the API or it does not.
#
# Normally the fields are not hand-written at all —
# scripts/ci/apply_deviation_approval.rb writes them in response to a real
# review. This gate is the check that the writing was legitimate.
#
# Deviations already approved on the base branch are NOT re-litigated; they
# were corroborated when they landed, and re-checking them would make every
# unrelated PR depend on a review of work it did not touch.
#
# On push/main the gate defers to branch protection.
#
# Exit 0 = no unapproved deviations, and every newly-approved one is corroborated.
# Exit 1 = a deviation awaits approval, or claims one that cannot be corroborated.

require "yaml"
require "json"

REPO_ROOT = File.expand_path("../..", __dir__)
FINDINGS  = ENV.fetch("SPARC_FINDINGS_FILE", File.join(REPO_ROOT, "docs/compliance/sparc-findings.yml"))
EVENT     = ENV["GITHUB_EVENT_NAME"].to_s
PR_NUM    = ENV["SPARC_PR_NUMBER"].to_s
BASE_REF  = ENV.fetch("SPARC_BASE_REF", "origin/main")
REPO_SLUG = ENV.fetch("SPARC_REPO", "risk-sentinel/sparc")

AUTHORISED_PERMISSIONS = %w[admin maintain].freeze

def load_findings(source)
  data = YAML.safe_load(source, permitted_classes: [ Date ], aliases: true)
  return {} unless data.is_a?(Hash)

  Array(data["findings"]).each_with_object({}) do |f, acc|
    next unless f.is_a?(Hash) && f["cve_id"]
    acc[f["cve_id"]] = f
  end
end

def risk_status(finding)
  finding.dig("deviation", "risk_status")
end

abort "✗ findings file not found: #{FINDINGS}" unless File.exist?(FINDINGS)

head = load_findings(File.read(FINDINGS))
base_source = `git show #{BASE_REF}:docs/compliance/sparc-findings.yml 2>/dev/null`
base = base_source.strip.empty? ? {} : load_findings(base_source)

awaiting = head.select { |_, f| risk_status(f) == "deviation-requested" }
newly_approved = head.select do |cve, f|
  next false unless risk_status(f) == "deviation-approved"
  before = base[cve]
  before.nil? || before["deviation"] != f["deviation"]
end

# ── Rule 1: nothing may still be awaiting approval ────────────────────────────
unless awaiting.empty?
  warn "✗ DEVIATION AWAITING APPROVAL"
  warn ""
  awaiting.each do |cve, f|
    warn "    #{cve}  #{f['severity']}  #{f.dig('deviation', 'type')}"
  end
  warn ""
  warn "  These emit `failed`, so a CRITICAL breaches threshold.yml. That is intended:"
  warn "  a deviation is a risk decision and needs an Authorizing Official."
  warn ""
  warn "  To approve: an admin submits an APPROVING REVIEW on this PR. The"
  warn "  deviation-approval workflow then records who approved, when, and on"
  warn "  which PR, and this gate turns green. Do not edit the approval fields"
  warn "  by hand — they are corroborated against the actual review."
  exit 1
end

if newly_approved.empty?
  puts "✓ No deviations awaiting approval, and none newly approved by this change."
  exit 0
end

puts "Deviations newly approved by this change:"
newly_approved.each { |cve, f| puts "  - #{cve}  #{f['severity']}  #{f.dig('deviation', 'type')}" }
puts

unless %w[pull_request pull_request_review].include?(EVENT)
  puts "✓ Not a pull-request event — approval is enforced by branch protection at merge."
  exit 0
end

if PR_NUM.empty?
  warn "✗ SPARC_PR_NUMBER is not set; cannot corroborate the approval."
  exit 1
end

# ── Rule 2: corroborate each claimed approval against a real review ───────────
raw = `gh pr view #{PR_NUM} --json latestReviews 2>/dev/null`
approvers =
  begin
    Array(JSON.parse(raw)["latestReviews"])
      .select { |r| r["state"] == "APPROVED" }
      .filter_map { |r| r.dig("author", "login")&.downcase }
  rescue JSON::ParserError
    []
  end

failures = []
bypassed = []
newly_approved.each do |cve, f|
  claimed = f.dig("deviation", "approved_by").to_s.sub(/\A@/, "").downcase
  if claimed.empty?
    failures << "#{cve}: claims deviation-approved but names no approver"
    next
  end

  # INTERIM PATH — admin merge bypass.
  #
  # GitHub does not allow anyone to approve their own pull request. In a
  # single-admin repository the admin is usually also the author, so the
  # review-based corroboration below is unreachable and the only route is an
  # admin merge past the red gate. Rather than let that happen silently — which
  # is how #863 landed eight approvals nobody had granted — the register must
  # declare it: `approval_mechanism: admin-merge-bypass`.
  #
  # This is WEAKER than review corroboration. It proves the named approver holds
  # authority, not that a distinct approval event occurred. It is accepted only
  # until the mechanized `/approve-deviation` flow lands (#871), which restores
  # a separate, attributable approval act.
  if f.dig("deviation", "approval_mechanism") == "admin-merge-bypass"
    perm_raw = `gh api repos/#{REPO_SLUG}/collaborators/#{claimed}/permission 2>/dev/null`
    permission =
      begin
        JSON.parse(perm_raw).fetch("permission", "")
      rescue JSON::ParserError
        ""
      end
    if AUTHORISED_PERMISSIONS.include?(permission)
      bypassed << "#{cve}: approved by @#{claimed} (#{permission}) via admin merge bypass"
    else
      failures << "#{cve}: declares admin-merge-bypass but @#{claimed} holds '#{permission.empty? ? 'unknown' : permission}'"
    end
    next
  end

  unless approvers.include?(claimed)
    failures << "#{cve}: claims approval by @#{claimed}, who has not submitted an approving review on this PR"
    next
  end

  perm_raw = `gh api repos/#{REPO_SLUG}/collaborators/#{claimed}/permission 2>/dev/null`
  permission =
    begin
      JSON.parse(perm_raw).fetch("permission", "")
    rescue JSON::ParserError
      ""
    end
  unless AUTHORISED_PERMISSIONS.include?(permission)
    failures << "#{cve}: @#{claimed} holds '#{permission.empty? ? 'unknown' : permission}', not #{AUTHORISED_PERMISSIONS.join('/')}"
  end
end

if failures.empty?
  unless bypassed.empty?
    puts "⚠ APPROVED VIA ADMIN MERGE BYPASS — not by a distinct approval event"
    puts
    bypassed.each { |b| puts "    #{b}" }
    puts
    puts "  GitHub forbids approving your own PR, so a single-admin repo cannot use the"
    puts "  review path. Authority is verified; a separate approval act is not. This is"
    puts "  recorded in the register as approval_mechanism: admin-merge-bypass so the"
    puts "  evidence says how it was approved, and is superseded by the mechanized"
    puts "  /approve-deviation flow (#871)."
    puts
  end
  corroborated = newly_approved.size - bypassed.size
  if corroborated.positive?
    puts "✓ #{corroborated} deviation(s) corroborated by an approving review from an authorised reviewer."
    puts "  Approving reviewers on this PR: #{approvers.join(', ')}"
  end
  puts "✓ No unapproved or unauthorised deviations."
  exit 0
end

warn "✗ DEVIATION APPROVAL NOT CORROBORATED"
warn ""
failures.each { |f| warn "    #{f}" }
warn ""
warn "  Approving reviewers on this PR: #{approvers.empty? ? '(none)' : approvers.join(', ')}"
warn "  The approval fields must describe a review that actually happened."
exit 1
