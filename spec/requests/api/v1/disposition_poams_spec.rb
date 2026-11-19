# frozen_string_literal: true

require "rails_helper"

# #1368 — GET /api/v1/authorization_boundaries/:id/disposition_poam: the
# dispositions as an OSCAL POA&M in NIST's vocabulary. hdf is stubbed with the
# POA&M hdf-cli 3.8.0 really produced; the document is still schema-validated.
RSpec.describe "Api::V1 disposition POA&M", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:scan_run) { create(:scan_run, authorization_boundary: boundary) }
  let(:path) { "/api/v1/authorization_boundaries/#{boundary.slug}/disposition_poam" }
  let(:admin) { create(:user, :admin) }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  def dispositioned(control_id, *traits, kind:)
    create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
           control_id: control_id, severity: "HIGH")
    create(:finding_disposition, *traits, authorization_boundary: boundary, control_id: control_id, kind: kind)
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    hdf_poam = JSON.parse(Rails.root.join("spec/fixtures/files/hdf/oscal_poam_from_amendments_v3.8.0.json").read)
                   .except("_provenance")
    allow_any_instance_of(HdfRunner).to receive(:amend_verify).and_return(true)
    allow_any_instance_of(HdfRunner).to receive(:convert).and_return(hdf_poam)
  end

  it "returns the POA&M with the NIST status the user picked" do
    dispositioned("CVE-2026-0001", kind: "vendorDependency")
    get path, headers: headers_for(admin)

    expect(response).to have_http_status(:ok)
    risks = response.parsed_body.dig("plan-of-action-and-milestones", "risks")
    vendor = risks.find { |r| r["props"].any? { |p| p["value"] == "CVE-2026-0001" } }
    expect(vendor["status"]).to eq("deviation-requested")
    expect(vendor.dig("remediations", 0, "props", 0, "value")).to eq("transfer")
  end

  it "refuses, naming each disposition and the NIST fields it lacks" do
    dispositioned("CVE-2026-0001", :without_nist, kind: "poam")
    get path, headers: headers_for(admin)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["missing_nist_fields"]).to eq("CVE-2026-0001" => FindingDisposition::NIST_FIELDS.map(&:to_s))
    expect(response.parsed_body["details"]).to include("CVE-2026-0001")
  end

  it "refuses a caller without evidence.read on the boundary" do
    dispositioned("CVE-2026-0001", kind: "poam")
    get path, headers: headers_for(create(:user))

    expect(response).to have_http_status(:forbidden)
  end

  it "allows a caller who holds evidence.read on the boundary" do
    dispositioned("CVE-2026-0001", kind: "poam")
    reader = create(:user)
    grant_permission(reader, "evidence.read", authorization_boundary: boundary)
    get path, headers: headers_for(reader)

    expect(response).to have_http_status(:ok)
  end
end
