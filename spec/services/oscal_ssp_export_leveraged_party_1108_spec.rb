# frozen_string_literal: true

require "rails_helper"

# #1108 — the 1.2.3 sweep found a freshly exported SSP whose
# leveraged-authorization `party-uuid` resolved to no party: a legacy
# SspLeveragedAuthorization carries its own stored party_uuid, and nothing
# declared it in metadata.parties.
RSpec.describe OscalSspExportService, "leveraged-authorization parties" do
  let(:ssp) { create(:ssp_document) }

  def exported = JSON.parse(described_class.new(ssp).export_unvalidated)["system-security-plan"]

  it "declares the stored party of a legacy leveraged authorization" do
    la = create(:ssp_leveraged_authorization, ssp_document: ssp, party_uuid: SecureRandom.uuid)

    doc = exported
    party_ids = doc.dig("metadata", "parties").map { |p| p["uuid"] }

    expect(doc.dig("system-implementation", "leveraged-authorizations").map { |e| e["party-uuid"] }).to eq([ la.party_uuid ])
    expect(party_ids).to include(la.party_uuid)
  end

  it "conforms: no party reference dangles" do
    create(:ssp_leveraged_authorization, ssp_document: ssp, party_uuid: SecureRandom.uuid)

    result = OscalConformanceService.new({ "system-security-plan" => exported }, model: "system-security-plan").validate

    expect(result.violations.map(&:message).grep(/resolves to no party/)).to be_empty
  end

  it "declares each party once" do
    shared = SecureRandom.uuid
    create(:ssp_leveraged_authorization, ssp_document: ssp, party_uuid: shared)
    create(:ssp_leveraged_authorization, ssp_document: ssp, party_uuid: shared)

    expect(exported.dig("metadata", "parties").count { |p| p["uuid"] == shared }).to eq(1)
  end
end
