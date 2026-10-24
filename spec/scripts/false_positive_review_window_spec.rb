# frozen_string_literal: true

require "rails_helper"
require "open3"
require "tmpdir"
require "json"

# Loaded in-process as well as run as a subprocess below, so the window check
# runs where coverage can see it (the script guards `main`).
require Rails.root.join("bin/sparc_findings_to_hdf_amendments.rb").to_s

# Owner, 2026-10-24: a false_positive carries a 365-day review window. Its
# next_review_date becomes the amendment's `expiresAt`, so on day 366
# `hdf amend verify` drops it and security_gate fails until it is re-reviewed.
# The converter caps the window; it does not add a second overdue check.
RSpec.describe "False-positive review window (365 days)" do
  let(:amender) { Rails.root.join("bin/sparc_findings_to_hdf_amendments.rb").to_s }

  around do |example|
    Dir.mktmpdir("fp-window-spec-") { |dir| @dir = dir; example.run }
  end

  def amend(next_review:, discovery: "2026-09-24", last_reviewed: nil, today: "2026-10-24")
    yaml = <<~YAML
      findings:
      - cve_id: CVE-2099-0001
        package: sparc (application code)
        installed_version: n/a
        fixed_version: n/a
        severity: HIGH
        disposition: false_positive
        rationale: 'Invented: not a vulnerability.'
        nist_control: sc-23
        reviewed_by: '@invented-reviewer'
        discovery_date: '#{discovery}'
        #{"last_reviewed_date: '#{last_reviewed}'" if last_reviewed}
        next_review_date: '#{next_review}'
    YAML
    input = File.join(@dir, "findings.yml")
    File.write(input, yaml)
    out = File.join(@dir, "amendments.json")
    stdout, status = Open3.capture2e("ruby", amender, "--input", input, "--output", out, "--today", today)
    [ stdout, status, (File.exist?(out) ? File.read(out) : "") ]
  end

  it "accepts a window of exactly 365 days and carries it as the amendment's expiry" do
    _out, status, json = amend(discovery: "2026-10-24", next_review: "2027-10-24")

    expect(status).to be_success
    expect(json).to include('"expiresAt": "2027-10-24T00:00:00Z"')
  end

  it "refuses a window of 366 days" do
    out, status, = amend(discovery: "2026-10-24", next_review: "2027-10-25")

    expect(status).not_to be_success
    expect(out).to include("CVE-2099-0001: false_positive review window is 366d from discovery_date 2026-10-24 — policy max is 365d")
  end

  it "counts from the last re-review, not from discovery" do
    _out, status, = amend(discovery: "2025-06-01", last_reviewed: "2026-10-24", next_review: "2027-10-24")
    expect(status).to be_success

    out, status, = amend(discovery: "2025-06-01", next_review: "2027-10-24")
    expect(status).not_to be_success
    expect(out).to match(/review window is \d+d from discovery_date 2025-06-01/)
  end

  it "refuses a re-review dated before discovery" do
    out, status, = amend(discovery: "2026-09-24", last_reviewed: "2026-09-01", next_review: "2027-08-01")
    expect(status).not_to be_success
    expect(out).to include("is before discovery_date 2026-09-24")
  end

  # The HDF expiry is the gate; the converter does not fail a lapsed date twice.
  it "leaves a lapsed false positive to the HDF expiry rather than failing here" do
    _out, status, json = amend(discovery: "2025-10-24", next_review: "2026-10-24", today: "2026-10-25")

    expect(status).to be_success
    expect(json).to include('"expiresAt": "2026-10-24T00:00:00Z"')
  end

  describe "validate! in-process" do
    def errors_for(next_review:, discovery: "2026-10-24", last_reviewed: nil, today: Date.new(2026, 10, 24))
      finding = {
        "cve_id" => "CVE-2099-0001", "package" => "sparc (application code)",
        "severity" => "HIGH", "disposition" => "false_positive",
        "rationale" => "Invented: not a vulnerability.", "nist_control" => "sc-23",
        "reviewed_by" => "@invented-reviewer", "discovery_date" => discovery,
        "last_reviewed_date" => last_reviewed, "next_review_date" => next_review
      }
      validate!(finding, [], today: today)
    end

    it "takes 365 days and refuses 366" do
      expect(errors_for(next_review: "2027-10-24")).to be_empty
      expect(errors_for(next_review: "2027-10-25")).to eq(
        [ "CVE-2099-0001: false_positive review window is 366d from discovery_date 2026-10-24 — policy max is 365d" ]
      )
    end

    it "counts from last_reviewed_date when there is one" do
      expect(errors_for(discovery: "2025-06-01", last_reviewed: "2026-10-24", next_review: "2027-10-24")).to be_empty
      expect(errors_for(discovery: "2025-06-01", last_reviewed: "2026-10-23", next_review: "2027-10-24")).to eq(
        [ "CVE-2099-0001: false_positive review window is 366d from last_reviewed_date 2026-10-23 — policy max is 365d" ]
      )
    end

    it "refuses a re-review dated before discovery" do
      expect(errors_for(discovery: "2026-09-24", last_reviewed: "2026-09-01", next_review: "2027-08-01"))
        .to include("CVE-2099-0001: last_reviewed_date 2026-09-01 is before discovery_date 2026-09-24")
    end

    it "reports only the missing date when next_review_date is absent" do
      expect(errors_for(next_review: nil)).to eq([ "CVE-2099-0001: next_review_date is required" ])
    end

    it "does not fail a lapsed false positive; the HDF expiry does" do
      expect(errors_for(discovery: "2025-10-24", next_review: "2026-10-24", today: Date.new(2026, 10, 25))).to be_empty
    end
  end
end
