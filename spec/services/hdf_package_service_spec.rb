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

  # #1325 — amendments ride the package only when hdf verifies them.
  describe "amendments" do
    it "carries them when hdf amend verify accepts them" do
      allow_any_instance_of(HdfRunner).to receive(:amend_verify).and_return(true)
      amendments = described_class.new(boundary).build["payload"]["amendments"]
      expect(amendments["overrides"].map { |o| o["requirementId"] }).to eq(%w[CVE-1])
    end

    it "leaves them out when hdf amend verify rejects them" do
      allow_any_instance_of(HdfRunner).to receive(:amend_verify).and_raise(
        HdfRunner::Error.new("invalid", command: "hdf amend verify", exit_code: 1, stderr: "bad")
      )
      payload = described_class.new(boundary).build["payload"]
      expect(payload).not_to have_key("amendments")
      expect(payload["dispositions"].first["control_id"]).to eq("CVE-1")
    end

    it "leaves them out when the boundary has nothing to export" do
      empty = create(:authorization_boundary)
      expect(described_class.new(empty).build["payload"]).not_to have_key("amendments")
    end

    it "carries amendments the real hdf verifies" do
      skip "hdf-cli not on PATH (see #835)" unless HdfSystemExportService.cli_available?
      expect(described_class.new(boundary).build["payload"]["amendments"]["overrides"].size).to eq(1)
    end
  end

  it "is tamper-evident — the signature changes when content changes" do
    sig1 = described_class.new(boundary).build["signature"]
    create(:scanner_finding, :failed, scan_run: run, authorization_boundary: boundary, control_id: "CVE-2")
    sig2 = described_class.new(boundary).build["signature"]
    expect(sig2).not_to eq(sig1)
  end
end
