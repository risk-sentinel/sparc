#!/usr/bin/env ruby
# frozen_string_literal: true

# #865 — record an admin's PR review as the FedRAMP deviation approval.
#
# The loop this implements:
#
#   1. A PR adds a deviation as `deviation-requested`. The amendments tool emits
#      `failed` for it, so a CRITICAL breaches threshold.yml and the build is red.
#   2. Red blocks the merge for everyone without admin rights.
#   3. An admin submits an APPROVING REVIEW on the PR. That review is the
#      Authorizing Official approval — the decision point FedRAMP requires.
#   4. This script runs on `pull_request_review`, verifies the reviewer really
#      holds admin/maintain on the repo, then flips the requested deviations to
#      `deviation-approved` and stamps the provenance it derives from the review
#      event: who approved, when, and on which PR.
#   5. The change is pushed back to the PR branch and the gate goes green.
#   6. Any code approver can then merge normally.
#
# Approval is therefore never asserted by the PR author. It is written only in
# response to a real review by someone with real authority, and the recorded
# fields describe an event that actually happened. That is the whole point: the
# previous design let a PR claim `deviation-approved` before any review existed,
# and #863 merged eight such claims — including a CVSS 10.0 — with the register
# asserting an approval that never occurred.
#
# Why this pushes rather than leaving CI to re-run: pushes made with
# GITHUB_TOKEN deliberately do not trigger new workflow runs, so the caller
# runs the verification gate in this same job after the flip.
#
# Exit 0 — nothing to do, or approval applied successfully.
# Exit 1 — the reviewer lacks authority, or the update could not be written.

require "yaml"
require "json"

REPO_ROOT = File.expand_path("../..", __dir__)
FINDINGS  = ENV.fetch("SPARC_FINDINGS_FILE", File.join(REPO_ROOT, "docs/compliance/sparc-findings.yml"))

REVIEW_STATE = ENV["SPARC_REVIEW_STATE"].to_s.upcase
REVIEWER     = ENV["SPARC_REVIEWER"].to_s
REVIEWED_AT  = ENV["SPARC_REVIEWED_AT"].to_s
PR_NUMBER    = ENV["SPARC_PR_NUMBER"].to_s
REPO_SLUG    = ENV.fetch("SPARC_REPO", "risk-sentinel/sparc")

# Repo permission levels that may authorise a deviation.
AUTHORISED_PERMISSIONS = %w[admin maintain].freeze

def die(msg)
  warn "✗ #{msg}"
  exit 1
end

unless REVIEW_STATE == "APPROVED"
  puts "Review state is #{REVIEW_STATE.empty? ? '(none)' : REVIEW_STATE} — only an APPROVED review authorises a deviation. Nothing to do."
  exit 0
end

die "findings file not found: #{FINDINGS}" unless File.exist?(FINDINGS)

data = YAML.safe_load(File.read(FINDINGS), permitted_classes: [ Date ], aliases: true)
pending = Array(data && data["findings"]).select do |f|
  f.is_a?(Hash) && f.dig("deviation", "risk_status") == "deviation-requested"
end

if pending.empty?
  puts "✓ No deviations are awaiting approval. Nothing to do."
  exit 0
end

puts "Deviations awaiting approval:"
pending.each { |f| puts "  - #{f['cve_id']}  #{f['severity']}  #{f.dig('deviation', 'type')}" }
puts

# Authority check. A review from someone without admin/maintain is a normal code
# review, not an AO decision, and must not move the deviation.
die "SPARC_REVIEWER is not set" if REVIEWER.empty?

raw = `gh api repos/#{REPO_SLUG}/collaborators/#{REVIEWER}/permission 2>/dev/null`
permission =
  begin
    JSON.parse(raw).fetch("permission", "")
  rescue JSON::ParserError
    ""
  end

unless AUTHORISED_PERMISSIONS.include?(permission)
  die "#{REVIEWER} has repo permission '#{permission.empty? ? 'unknown' : permission}'. " \
      "A deviation may only be approved by #{AUTHORISED_PERMISSIONS.join(' or ')}. " \
      "The approving review stands as a code review; the deviation remains requested."
end

puts "Reviewer #{REVIEWER} holds '#{permission}' — authorised to approve a deviation."

approved_at = REVIEWED_AT.empty? ? Time.now.utc.strftime("%Y-%m-%d") : REVIEWED_AT[0, 10]
approved_in = "#{REPO_SLUG}##{PR_NUMBER}"
targets     = pending.map { |f| f["cve_id"] }.to_set

# Line-based edit: the register is comment-rich and a YAML round-trip destroys it.
require "set"
lines = File.readlines(FINDINGS)
out = []
current = nil
flipped = 0

lines.each do |line|
  current = Regexp.last_match(1) if line =~ /^  - cve_id:\s*(\S+)\s*$/

  if current && targets.include?(current) && line =~ /^      risk_status:\s*deviation-requested\s*$/
    out << "      risk_status: deviation-approved\n"
    out << "      approved_by: \"@#{REVIEWER}\"\n"
    out << "      approved_in: \"#{approved_in}\"\n"
    out << "      approved_at: \"#{approved_at}\"\n"
    flipped += 1
    next
  end
  out << line
end

die "expected to flip #{pending.size} deviation(s) but flipped #{flipped}" unless flipped == pending.size

File.write(FINDINGS, out.join)

puts
puts "✓ Recorded #{flipped} deviation approval(s)"
puts "    approved_by: @#{REVIEWER} (#{permission})"
puts "    approved_in: #{approved_in}"
puts "    approved_at: #{approved_at}"
