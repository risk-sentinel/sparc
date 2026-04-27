# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PoamFindings", type: :request do
  let(:user) { create(:user) }
  let(:poam) { create(:poam_document, name: "Findings Test POAM") }

  before { sign_in_as(user) }

  describe "POST /poam_documents/:poam_document_id/poam_findings" do
    it "creates a finding with shared OSCAL arrays + audit emission" do
      expect {
        post poam_document_poam_findings_path(poam), params: {
          poam_finding: { title: "AU-2 coverage gap",
                          description: "Audit events missing for new subsystem",
                          implementation_statement_uuid: "stmt-uuid-1",
                          props_data: [ { name: "ctrl", value: "au-2" } ],
                          links_data: [ { href: "https://gov/au2.pdf", rel: "reference" } ] }
        }
      }.to change { poam.poam_findings.count }.by(1)
        .and change { AuditEvent.where(action: "poam_finding_created").count }.by(1)

      finding = poam.poam_findings.last
      expect(finding.title).to eq("AU-2 coverage gap")
      expect(finding.implementation_statement_uuid).to eq("stmt-uuid-1")
      expect(finding.props_data.first).to eq({ "name" => "ctrl", "value" => "au-2" })
    end
  end

  describe "POST with target_data (#424)" do
    it "stores the OSCAL finding-target with status.state in JSONB" do
      post poam_document_poam_findings_path(poam), params: {
        poam_finding: { title: "Target Test", description: "—",
                        target_data: { type: "statement-id",
                                       :"target-id" => "ac-2_smt.a",
                                       status: { state: "not-satisfied",
                                                 remarks: "Missing audit hooks" } } }
      }

      finding = poam.poam_findings.find_by(title: "Target Test")
      expect(finding.target_data).to eq({
        "type" => "statement-id",
        "target-id" => "ac-2_smt.a",
        "status" => { "state" => "not-satisfied", "remarks" => "Missing audit hooks" }
      })
    end

    it "drops the status sub-hash when state is blank" do
      post poam_document_poam_findings_path(poam), params: {
        poam_finding: { title: "No Status Test", description: "—",
                        target_data: { type: "objective-id",
                                       :"target-id" => "ac-2_obj",
                                       status: { state: "", remarks: "" } } }
      }

      finding = poam.poam_findings.find_by(title: "No Status Test")
      expect(finding.target_data).to eq({
        "type" => "objective-id",
        "target-id" => "ac-2_obj"
      })
      expect(finding.target_data).not_to have_key("status")
    end
  end

  describe "DELETE /poam_documents/:poam_document_id/poam_findings/:id" do
    let!(:finding) { poam.poam_findings.create!(uuid: SecureRandom.uuid, title: "Doomed") }

    it "destroys and writes audit row" do
      expect {
        delete poam_document_poam_finding_path(poam, finding)
      }.to change { poam.poam_findings.count }.by(-1)
        .and change { AuditEvent.where(action: "poam_finding_deleted").count }.by(1)
    end
  end
end
