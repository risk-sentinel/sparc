# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::FindingDispositions", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  let(:boundary) { create(:authorization_boundary) }
  let(:scan_run) { create(:scan_run, authorization_boundary: boundary) }
  let(:finding) do
    create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
           control_id: "CVE-1", severity: "HIGH")
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def disposition_path
    api_v1_scanner_finding_disposition_path(finding.uuid)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      post disposition_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST .../disposition" do
    it "creates a falsePositive disposition linked to Evidence" do
      evidence = create(:evidence)
      post disposition_path,
           params: { kind: "falsePositive", reason: "scanner wrong",
                     linked_subject_type: "Evidence", linked_subject_id: evidence.id },
           headers: admin_headers

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["kind"]).to eq("falsePositive")
      expect(data["hdf_status"]).to eq("notApplicable")
      expect(data["signature_hash"]).to be_present
      expect(data["decided_by"]).to eq(admin.display_name.presence || admin.email)
    end

    it "acts as an upsert on repeat POST" do
      evidence = create(:evidence)
      poam = create(:poam_finding)
      post disposition_path, params: { kind: "poam", reason: "tracked",
                                       linked_subject_type: "PoamFinding", linked_subject_id: poam.id },
           headers: admin_headers
      post disposition_path, params: { kind: "falsePositive", reason: "actually FP",
                                       linked_subject_type: "Evidence", linked_subject_id: evidence.id },
           headers: admin_headers

      expect(FindingDisposition.where(authorization_boundary: boundary, control_id: "CVE-1").count).to eq(1)
      expect(JSON.parse(response.body)["data"]["kind"]).to eq("falsePositive")
    end

    it "returns 422 when the linkage is wrong" do
      post disposition_path, params: { kind: "poam", reason: "x",
                                       linked_subject_type: "Evidence", linked_subject_id: create(:evidence).id },
           headers: admin_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/must link a PoamFinding/)
    end

    it "returns 422 for a waiver on a CRITICAL finding" do
      crit = create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
                    control_id: "CVE-CRIT", severity: "CRITICAL")
      ao = create(:attestation, role: "authorizing_official")
      post api_v1_scanner_finding_disposition_path(crit.uuid),
           params: { kind: "waiver", reason: "x", linked_subject_type: "Attestation",
                     linked_subject_id: ao.id, expiration: 90.days.from_now.iso8601 },
           headers: admin_headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to match(/CRITICAL/)
    end

    it "forbids a member without evidence.write" do
      post disposition_path, params: { kind: "falsePositive", reason: "x",
                                       linked_subject_type: "Evidence", linked_subject_id: create(:evidence).id },
           headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET .../disposition" do
    it "shows the current disposition" do
      create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-1", kind: "poam")
      get disposition_path, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["kind"]).to eq("poam")
    end

    it "returns 404 when undispositioned" do
      get disposition_path, headers: admin_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE .../disposition" do
    it "clears the disposition" do
      create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-1", kind: "poam")
      delete disposition_path, headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(FindingDisposition.where(authorization_boundary: boundary, control_id: "CVE-1")).to be_empty
    end
  end

  describe "approval flow (#809)" do
    before { create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-1", kind: "poam") }

    it "approves the disposition (records approver)" do
      post approve_api_v1_scanner_finding_disposition_path(finding.uuid), headers: admin_headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["approval_status"]).to eq("approved")
      expect(data["approved_by"]).to be_present
    end

    it "rejects the disposition" do
      post reject_api_v1_scanner_finding_disposition_path(finding.uuid), headers: admin_headers
      expect(JSON.parse(response.body)["data"]["approval_status"]).to eq("rejected")
    end

    it "forbids a member without amendment.approve" do
      post approve_api_v1_scanner_finding_disposition_path(finding.uuid), headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end

    it "re-creating a disposition resets approval to draft" do
      post approve_api_v1_scanner_finding_disposition_path(finding.uuid), headers: admin_headers
      post disposition_path, params: { kind: "poam", reason: "changed",
                                       linked_subject_type: "PoamFinding", linked_subject_id: create(:poam_finding).id },
           headers: admin_headers
      expect(JSON.parse(response.body)["data"]["approval_status"]).to eq("draft")
    end
  end
end
