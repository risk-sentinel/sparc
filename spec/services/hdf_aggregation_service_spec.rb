# frozen_string_literal: true

require "rails_helper"

RSpec.describe HdfAggregationService do
  let(:boundary) { create(:authorization_boundary) }
  let(:run)      { create(:scan_run, authorization_boundary: boundary) }

  def failed_finding(nist:, control_id: "CVE-1", **kw)
    create(:scanner_finding, :failed, scan_run: run, authorization_boundary: boundary,
           control_id: control_id, raw_hdf: { "tags" => { "nist" => Array(nist) } }, **kw)
  end

  it "annotates matching SSP/SAR/SAP controls (non-destructive) via NIST tags" do
    ssp = create(:ssp_document, authorization_boundary: boundary)
    create(:ssp_control, ssp_document: ssp, control_id: "AC-2")
    sar = create(:sar_document, authorization_boundary: boundary)
    create(:sar_control, sar_document: sar, control_id: "AC-2")
    failed_finding(nist: [ "AC-2" ])

    result = described_class.new(boundary).aggregate
    expect(result.ssp).to eq(1)
    expect(result.sar).to eq(1)

    field = ssp.ssp_controls.first.ssp_control_fields.find_by(field_name: "hdf_scan_result")
    expect(field.field_value).to include("failed")
  end

  it "tracks failed findings as POA&M findings, skipping suppressed ones" do
    poam = create(:poam_document, authorization_boundary: boundary)
    failed_finding(nist: [ "AC-2" ], control_id: "CVE-1")
    failed_finding(nist: [ "AC-3" ], control_id: "CVE-2")
    create(:finding_disposition, :false_positive, authorization_boundary: boundary, control_id: "CVE-2",
           linked_subject: create(:evidence), approval_status: "approved", approved_by: "ao",
           valid_until: 30.days.from_now)

    result = described_class.new(boundary).aggregate
    expect(result.poam).to eq(1) # CVE-1 tracked; CVE-2 suppressed by an applicable false-positive
    expect(poam.poam_findings.pluck(:title)).to contain_exactly("HDF: CVE-1")
  end

  it "opens a POA&M item once a suppressing waiver has expired" do
    poam = create(:poam_document, authorization_boundary: boundary)
    failed_finding(nist: [ "AC-2" ], control_id: "CVE-LAPSED")
    create(:finding_disposition, :waiver, authorization_boundary: boundary,
           control_id: "CVE-LAPSED", approval_status: "approved", approved_by: "ao",
           expiration: 1.day.ago, valid_until: 30.days.from_now)

    result = described_class.new(boundary).aggregate
    expect(result.poam).to eq(1)
    expect(poam.poam_findings.pluck(:title)).to contain_exactly("HDF: CVE-LAPSED")
  end

  it "is idempotent (upserts, no duplicates on re-run)" do
    ssp = create(:ssp_document, authorization_boundary: boundary)
    create(:ssp_control, ssp_document: ssp, control_id: "AC-2")
    failed_finding(nist: [ "AC-2" ])

    described_class.new(boundary).aggregate
    expect { described_class.new(boundary).aggregate }.not_to change(SspControlField, :count)
  end

  it "returns zero counts when the boundary has no documents" do
    result = described_class.new(boundary).aggregate
    expect(result.to_h).to eq(ssp: 0, sar: 0, sap: 0, poam: 0)
  end
end
