# frozen_string_literal: true

require "rails_helper"

RSpec.describe HdfPackageService do
  let(:boundary) { create(:authorization_boundary) }
  let(:run)      { create(:scan_run, authorization_boundary: boundary) }

  before do
    create(:scanner_finding, :failed, scan_run: run, authorization_boundary: boundary, control_id: "CVE-1")
    create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-1", kind: "poam")
  end

  it "builds a bundle with amendments, findings, and dispositions" do
    bundle = described_class.new(boundary).build
    expect(bundle["payload"]["format"]).to eq("sparc-hdf-package/v1")
    expect(bundle["payload"]["boundary"]["slug"]).to eq(boundary.slug)
    expect(bundle["payload"]["findings"].first["control_id"]).to eq("CVE-1")
    expect(bundle["payload"]["dispositions"].first["kind"]).to eq("poam")
    expect(bundle["algorithm"]).to eq("HMAC-SHA256")
    expect(bundle["signature"]).to be_present
  end

  it "signs the encoded payload verifiably (SparcKeyDerivation HMAC)" do
    bundle = described_class.new(boundary).build
    key = SparcKeyDerivation.derive("hdf-package-signing-v1")
    expected = OpenSSL::HMAC.hexdigest("SHA256", key, bundle["encoded_payload"])
    expect(bundle["signature"]).to eq(expected)
  end

  it "is tamper-evident — the signature changes when content changes" do
    sig1 = described_class.new(boundary).build["signature"]
    create(:scanner_finding, :failed, scan_run: run, authorization_boundary: boundary, control_id: "CVE-2")
    sig2 = described_class.new(boundary).build["signature"]
    expect(sig2).not_to eq(sig1)
  end
end
