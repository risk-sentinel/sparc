# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScannerFinding do
  it "has a valid factory" do
    expect(build(:scanner_finding)).to be_valid
  end

  it "requires a control_id and status" do
    expect(build(:scanner_finding, control_id: nil)).not_to be_valid
    expect(build(:scanner_finding, status: nil)).not_to be_valid
  end

  it "is unique per (authorization_boundary, control_id)" do
    boundary = create(:authorization_boundary)
    run = create(:scan_run, authorization_boundary: boundary)
    create(:scanner_finding, scan_run: run, authorization_boundary: boundary, control_id: "CVE-2026-1234")

    dup = build(:scanner_finding, scan_run: run, authorization_boundary: boundary, control_id: "CVE-2026-1234")
    expect(dup).not_to be_valid
  end

  it "allows history rows (current: false) to share (boundary, control_id) — #811" do
    boundary = create(:authorization_boundary)
    run1 = create(:scan_run, authorization_boundary: boundary)
    run2 = create(:scan_run, authorization_boundary: boundary)
    create(:scanner_finding, :history, scan_run: run1, authorization_boundary: boundary, control_id: "CVE-1")
    current = build(:scanner_finding, scan_run: run2, authorization_boundary: boundary, control_id: "CVE-1")
    expect(current).to be_valid # one current + one history row is allowed
  end

  it "still rejects two CURRENT findings for the same (boundary, control_id)" do
    boundary = create(:authorization_boundary)
    run = create(:scan_run, authorization_boundary: boundary)
    create(:scanner_finding, scan_run: run, authorization_boundary: boundary, control_id: "CVE-1")
    dup = build(:scanner_finding, scan_run: run, authorization_boundary: boundary, control_id: "CVE-1")
    expect(dup).not_to be_valid
  end

  it "allows the same control_id in a different boundary" do
    finding = create(:scanner_finding, control_id: "CVE-2026-1234")
    other_boundary = create(:authorization_boundary)
    other_run = create(:scan_run, authorization_boundary: other_boundary)
    dup = build(:scanner_finding, scan_run: other_run, authorization_boundary: other_boundary, control_id: "CVE-2026-1234")
    expect(dup).to be_valid
    expect(finding).to be_persisted
  end

  it "scopes to failed findings" do
    boundary = create(:authorization_boundary)
    run = create(:scan_run, authorization_boundary: boundary)
    create(:scanner_finding, :passed, scan_run: run, authorization_boundary: boundary)
    failed = create(:scanner_finding, :failed, scan_run: run, authorization_boundary: boundary)
    expect(boundary.scanner_findings.failed).to contain_exactly(failed)
  end

  describe "#disposition" do
    it "finds the disposition keyed by (boundary, control_id)" do
      boundary = create(:authorization_boundary)
      run = create(:scan_run, authorization_boundary: boundary)
      finding = create(:scanner_finding, scan_run: run, authorization_boundary: boundary, control_id: "CVE-2026-9")
      disp = create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-2026-9")

      expect(finding.disposition).to eq(disp)
      expect(finding).to be_dispositioned
    end

    it "returns nil when undispositioned" do
      expect(create(:scanner_finding).disposition).to be_nil
    end
  end
end
