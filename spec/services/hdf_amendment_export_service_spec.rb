# frozen_string_literal: true

require "rails_helper"

RSpec.describe HdfAmendmentExportService do
  let(:boundary) { create(:authorization_boundary) }
  let(:scan_run) { create(:scan_run, authorization_boundary: boundary) }
  let(:runner)   { instance_double(HdfRunner, amend_verify: true) }
  let(:service)  { described_class.new(boundary, runner: runner) }

  # A dispositioned finding present in the current scan.
  def dispositioned(control_id, kind: "poam", **disp_attrs)
    create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
           control_id: control_id, severity: "HIGH")
    create(:finding_disposition, authorization_boundary: boundary, control_id: control_id,
           kind: kind, **disp_attrs)
  end

  describe "#export" do
    it "emits an Amendments doc with one override per current dispositioned finding" do
      dispositioned("CVE-1", kind: "poam", reason: "tracked", decided_by: "sec@corp.io")
      dispositioned("CVE-2", kind: "falsePositive", reason: "unreachable", decided_by: "@ghuser")

      doc = service.export

      expect(doc["version"]).to eq("1")
      expect(doc["labels"]["system_id"]).to eq(boundary.slug)
      expect(doc["overrides"].length).to eq(2)

      o1 = doc["overrides"].find { |o| o["requirementId"] == "CVE-1" }
      expect(o1["type"]).to eq("poam")
      expect(o1["status"]).to eq("failed")
      expect(o1["reason"]).to eq("tracked")
      expect(o1["appliedBy"]).to eq({ "type" => "email", "identifier" => "sec@corp.io" })

      o2 = doc["overrides"].find { |o| o["requirementId"] == "CVE-2" }
      expect(o2["type"]).to eq("falsePositive")
      expect(o2["status"]).to eq("notApplicable")
      expect(o2["appliedBy"]).to eq({ "type" => "github", "identifier" => "@ghuser" })
    end

    it "orders overrides by requirementId (deterministic)" do
      dispositioned("CVE-9")
      dispositioned("CVE-1")
      dispositioned("CVE-5")
      expect(service.export["overrides"].map { |o| o["requirementId"] }).to eq(%w[CVE-1 CVE-5 CVE-9])
    end

    it "includes expiresAt for time-bounded dispositions" do
      finding = create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
                       control_id: "CVE-W", severity: "HIGH")
      create(:finding_disposition, :waiver, authorization_boundary: boundary, control_id: finding.control_id,
             expiration: 90.days.from_now)
      override = service.export["overrides"].first
      expect(override["expiresAt"]).to be_present
    end

    it "excludes dispositions whose control_id is not in the current scan" do
      dispositioned("CVE-1")
      # A disposition with no matching finding in this boundary's scan:
      create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-GONE", kind: "poam")
      expect(service.export["overrides"].map { |o| o["requirementId"] }).to eq(%w[CVE-1])
    end

    it "excludes expired dispositions" do
      finding = create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
                       control_id: "CVE-EXP", severity: "HIGH")
      create(:finding_disposition, :waiver, authorization_boundary: boundary,
             control_id: finding.control_id, expiration: 1.day.ago)
      expect(service.export["overrides"]).to be_empty
    end

    it "is deterministic: same dispositions produce the same amendmentId" do
      dispositioned("CVE-1")
      id1 = service.export["amendmentId"]
      id2 = described_class.new(boundary, runner: runner).export["amendmentId"]
      expect(id1).to eq(id2)
    end

    it "validates the emitted doc via hdf amend verify" do
      dispositioned("CVE-1")
      expect(runner).to receive(:amend_verify).with(kind_of(String)).and_return(true)
      service.export
    end

    it "skips verification when verify: false" do
      dispositioned("CVE-1")
      expect(runner).not_to receive(:amend_verify)
      service.export(verify: false)
    end

    it "propagates a verification failure" do
      dispositioned("CVE-1")
      allow(runner).to receive(:amend_verify).and_raise(
        HdfRunner::Error.new("schema mismatch", command: "hdf amend verify", exit_code: 1, stderr: "bad")
      )
      expect { service.export }.to raise_error(HdfRunner::Error)
    end
  end
end
